import Foundation

public struct ConfigurationStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        return try Configuration.read(from: url)
    }
    public func save(_ configuration: Configuration) throws {
        let valid = try configuration.validated()
        let data = try JSONEncoder().encode(valid)
        try Configuration.validateSize(data.count)
        try PrivateFile.write(data, to: url)
    }
    public func importData(_ data: Data) throws -> Configuration {
        let candidate = try Configuration.decode(data)
        try save(candidate)
        return candidate
    }
}
