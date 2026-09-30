import Foundation

/// Deliberately excludes free-form messages, URLs, names, arguments and environment values.
public struct DiagnosticLog: Sendable {
    public enum Event: String, Codable, Sendable {
        case applicationStarted, configurationSaved, operationStatusChanged, errorPresented
    }
    public struct Entry: Codable, Sendable {
        public let date: Date
        public let event: Event
    }
    public private(set) var entries: [Entry] = []
    public let capacity: Int
    public init(capacity: Int = 500) { self.capacity = max(1, capacity) }
    public mutating func record(_ event: Event, at date: Date = Date()) {
        entries.append(.init(date: date, event: event))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }
}
