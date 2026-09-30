import Foundation
import Darwin

public struct TemplateLibrary: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public static let supportedExtensions = ["txt", "md", "json", "docx", "xlsx", "pptx", "pages", "numbers", "key"]
    private static let maximumBytes = 256 * 1024 * 1024

    public func importTemplateAsync(from source: URL, replacing existing: TemplateEntry? = nil) async throws -> TemplateEntry {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try importTemplate(from: source, replacing: existing)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Imports a private snapshot. Container checks cannot replace opening a document in its authoring application.
    public func importTemplate(from source: URL, replacing existing: TemplateEntry? = nil) throws -> TemplateEntry {
        try Task.checkCancellation()
        let ext = source.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { throw ConfigurationError.invalid("不支持的模板类型") }
        try Self.validateSource(source, extension: ext)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = root.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            try Self.validateSource(destination, extension: ext)
            try Task.checkCancellation()
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return TemplateEntry(id: existing?.id ?? UUID(), name: existing?.name ?? source.deletingPathExtension().lastPathComponent,
                             fileExtension: ext, source: destination, enabled: existing?.enabled ?? true)
    }
    /// Only remove a snapshot directly owned by this library, never a user's imported original.
    public func removeSnapshot(_ url: URL?) throws {
        guard let url, url.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { return }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    public static func validateSource(_ url: URL, extension ext: String) throws {
        try Task.checkCancellation()
        guard url.isLocalFileURL else { throw ConfigurationError.invalid("请选择文档文件") }
        guard supportedExtensions.contains(ext) else { throw ConfigurationError.invalid("不支持的模板类型") }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw ConfigurationError.invalid("模板不能是符号链接") }
        if values.isDirectory == true {
            guard ["pages", "numbers", "key"].contains(ext) else { throw ConfigurationError.invalid("请选择文档文件") }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, errorHandler: { _, error in
                enumerationError = error
                return false
            }) else {
                throw ConfigurationError.invalid("无法读取文档包")
            }
            var bytes = 0; var count = 0
            for case let child as URL in enumerator {
                try Task.checkCancellation()
                let attrs = try child.resourceValues(forKeys: Set(keys))
                guard attrs.isSymbolicLink != true else { throw ConfigurationError.invalid("文档包不能包含符号链接") }
                guard attrs.isDirectory == true || attrs.isRegularFile == true else {
                    throw ConfigurationError.invalid("请选择文档文件")
                }
                count += 1
                // Directory metadata is not document content. Empty nested folders
                // must not make an otherwise empty package appear valid.
                if attrs.isRegularFile == true { bytes += attrs.fileSize ?? 0 }
                guard count <= 100_000, bytes <= maximumBytes else { throw ConfigurationError.invalid("模板超过 256 MB 或项目过多") }
            }
            if let enumerationError { throw enumerationError }
            guard count > 0, bytes > 0 else { throw ConfigurationError.invalid("文档包为空") }
            return
        }
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumBytes else {
            throw ConfigurationError.invalid("请选择不超过 256 MB 的文档")
        }
        // Recheck the opened object, not just metadata obtained before opening.
        // A replaced FIFO must not block; a growing file must not bypass the cap.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw ConfigurationError.invalid("请选择不超过 256 MB 的文档")
        }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw ConfigurationError.invalid("请选择不超过 256 MB 的文档") }
        try Task.checkCancellation()
        if ext == "json" {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } else if ext == "txt" || ext == "md" {
            guard String(data: data, encoding: .utf8) != nil else { throw ConfigurationError.invalid("文本模板需使用 UTF-8 编码") }
        } else {
            let names = try archiveNames(data)
            let part: String?
            switch ext {
            case "docx": part = "word/document.xml"
            case "xlsx": part = "xl/workbook.xml"
            case "pptx": part = "ppt/presentation.xml"
            default: part = nil
            }
            if let part {
                guard names.contains("[Content_Types].xml"), names.contains("_rels/.rels"), names.contains(part) else {
                    throw ConfigurationError.invalid("Office 模板缺少必要的文档内容")
                }
            }
        }
    }
    /// Reads the ZIP directory only: no extraction, decompression or document execution.
    private static func archiveNames(_ data: Data) throws -> Set<String> {
        func invalid() -> ConfigurationError { .invalid("文档容器不完整，请从原应用重新保存后导入") }
        func uint16(_ i: Int) -> Int { Int(data[i]) | Int(data[i + 1]) << 8 }
        func uint32(_ i: Int) -> Int { uint16(i) | uint16(i + 2) << 16 }
        guard data.count >= 22 else { throw invalid() }
        let lower = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: lower, by: -1).first(where: {
            uint32($0) == 0x06054b50 && $0 + 22 + uint16($0 + 20) == data.count
        }) else { throw invalid() }
        let count = uint16(end + 10), start = uint32(end + 16), size = uint32(end + 12)
        guard uint16(end + 4) == 0, uint16(end + 6) == 0, uint16(end + 8) == count,
              count > 0, count < 65_535, start <= end, size <= end - start else { throw invalid() }
        var cursor = start; var names = Set<String>()
        for _ in 0..<count {
            try Task.checkCancellation()
            guard cursor <= end - 46, uint32(cursor) == 0x02014b50 else { throw invalid() }
            let nameLength = uint16(cursor + 28)
            let length = 46 + nameLength + uint16(cursor + 30) + uint16(cursor + 32)
            guard length <= end - cursor, uint16(cursor + 8) & 1 == 0,
                  let name = String(data: data[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { throw invalid() }
            names.insert(name); cursor += length
        }
        guard cursor == start + size else { throw invalid() }
        return names
    }
}
