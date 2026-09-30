import Foundation

extension URL {
    /// Paths passed to filesystem APIs must not discard a remote authority or URL suffix.
    /// Mounted network volumes remain supported through their local mount paths.
    public var isLocalFileURL: Bool {
        guard isFileURL,
              let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
              components.host == nil || components.host == "" || components.host?.lowercased() == "localhost",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return false }
        guard let decodedPath = components.percentEncodedPath.removingPercentEncoding else { return false }
        return decodedPath.hasPrefix("/") && !decodedPath.contains("\0")
    }
}
