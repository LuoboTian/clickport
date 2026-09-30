import Foundation
import Security

@objc(ClickportLaunchHelperProtocol)
protocol LaunchHelperProtocol {
    func launch(_ request: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}

enum LaunchPeerIdentity {
    static let serviceName = "org.clickport.LaunchHelper"

    /// Derive the team from this process's signature; no signing identity in source.
    /// Unsigned/ad-hoc processes fail closed, including unsigned development builds.
    static func requirement(identifier: String) throws -> String {
        var code: SecCode?
        var information: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw CocoaError(.executableNotLoadable)
        }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(identifier)\""
    }
}
