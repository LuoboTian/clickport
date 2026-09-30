import Foundation

public struct ReleaseLinks: Sendable {
    public let gitHub: URL?
    public let updates: URL?
    public let feedback: URL?
    public init(gitHub: String? = nil, updates: String? = nil, feedback: String? = nil) {
        self.gitHub = Self.webURL(gitHub)
        self.updates = Self.webURL(updates)
        self.feedback = Self.webURL(feedback)
    }
    private static func webURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let components = URLComponents(string: value), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil,
              let url = components.url else { return nil }
        return url
    }
}
