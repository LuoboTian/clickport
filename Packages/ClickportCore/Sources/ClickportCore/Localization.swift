import Foundation

public enum L10n {
    private static let languageBundles: [String: Bundle] = {
        guard let root = Bundle.module.resourceURL,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: Bundle] = [:]
        for folder in folders where folder.pathExtension == "lproj" {
            if let bundle = Bundle(url: folder) { result[folder.deletingPathExtension().lastPathComponent.lowercased()] = bundle }
        }
        return result
    }()
    public static func text(_ key: String, language: String? = nil) -> String {
        let bundle: Bundle
        if let language, let selected = languageBundles[language.lowercased()] {
            bundle = selected
        } else { bundle = .module }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    public static func format(_ key: String, _ arguments: String..., language: String? = nil) -> String {
        String(format: text(key, language: language), arguments: arguments.map { $0 as CVarArg })
    }
    public static func newFile(_ name: String) -> String { String(format: text("新建 %@"), name) }
}
