import Foundation
import Darwin

public enum FileOperations {
    /// Keeps file I/O off the caller's actor while forwarding cancellation to the
    /// worker. An in-flight copy finishes before cleanup; publication is skipped
    /// if cancellation is observed before the exclusive rename.
    public static func createAsync(template: TemplateEntry, in directory: URL) async throws -> URL {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try create(template: template, in: directory)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Copy valid imported documents as-is; only the three text formats have built-in contents.
    public static func create(template: TemplateEntry, in directory: URL) throws -> URL {
        try Task.checkCancellation()
        guard directory.isLocalFileURL,
              try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ConfigurationError.invalid("请选择可访问的目录")
        }
        var validation = Configuration()
        validation.templates = [template]
        _ = try validation.validated()
        if let source = template.source {
            try TemplateLibrary.validateSource(source, extension: template.fileExtension)
        }
        try Task.checkCancellation()
        // Prepare complete contents in an owned directory on the destination volume.
        // A failed package copy must never expose a partially created user document.
        let staging = directory.appendingPathComponent(".clickport-create-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let prepared = staging.appendingPathComponent("document.\(template.fileExtension)")
        if let source = template.source {
            try FileManager.default.copyItem(at: source, to: prepared)
            // Configuration imports and later source changes must not bypass the
            // same checks used by the native template importer. Validate the copy
            // too, before publishing it under its final document name.
            try TemplateLibrary.validateSource(prepared, extension: template.fileExtension)
        } else {
            let contents = template.fileExtension == "json" ? "{}\n" : ""
            try Data(contents.utf8).write(to: prepared, options: .withoutOverwriting)
        }
        for number in 1...10_000 {
            try Task.checkCancellation()
            let suffix = number == 1 ? "" : " \(number)"
            let target = directory.appendingPathComponent("Untitled\(suffix).\(template.fileExtension)")
            // Exclusive rename prevents a competing creation from being overwritten.
            if Darwin.renamex_np(prepared.path, target.path, UInt32(RENAME_EXCL)) == 0 {
                return target
            }
            let failure = errno
            if failure == EEXIST { continue }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        throw ConfigurationError.invalid("同名文件过多，请更改目标目录")
    }

    public static func setHidden(_ hidden: Bool, at url: URL) throws {
        guard url.isLocalFileURL, url.path != "/" else { throw ConfigurationError.invalid("目标不适用") }
        if !hidden && url.lastPathComponent.hasPrefix(".") {
            throw ConfigurationError.invalid("点开头的文件名仍会被 Finder 隐藏；此操作只修改隐藏属性，不更改文件名")
        }
        var target = url
        var values = URLResourceValues()
        values.isHidden = hidden
        try target.setResourceValues(values)
    }

    /// Immediate children only. Never traverse nested directories or symlink destinations.
    public static func hiddenChildren(in directory: URL) throws -> [URL] {
        guard directory.isLocalFileURL else { throw TargetError.notFileURL }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isHiddenKey])
            .filter { try $0.resourceValues(forKeys: [.isHiddenKey]).isHidden == true }
    }
}
