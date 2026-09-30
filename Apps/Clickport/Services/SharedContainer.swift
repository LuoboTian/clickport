import Foundation
import ClickportCore

/// Compiled in both targets. The group identifier is injected by the local build configuration.
enum SharedContainer {
    static func root() throws -> URL {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "ClickportAppGroup") as? String,
              !identifier.hasPrefix("."),
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw ConfigurationError.invalid("本地签名或共享容器不可用，请使用本机开发证书构建")
        }
        return url
    }
    static func store() throws -> ConfigurationStore { ConfigurationStore(url: try root().appendingPathComponent("configuration.json")) }
    static func inbox() throws -> URL {
        let url = try root().appendingPathComponent("Requests", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func submit(_ request: ActionRequest) throws {
        try request.validate()
        let data = try JSONEncoder().encode(request)
        guard data.count < RequestInbox.maximumBytes else { throw ConfigurationError.invalid("request size") }
        try PrivateFile.write(data, to: inbox().appendingPathComponent(request.id.uuidString + ".json"))
    }
}
