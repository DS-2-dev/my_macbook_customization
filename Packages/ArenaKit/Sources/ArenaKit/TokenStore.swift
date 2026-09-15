import Foundation
import Security

/// The Are.na personal access token, shared between the app (which saves it)
/// and the widget extension (which reads it) through the login keychain.
///
/// A free Apple ID can't use App Groups or keychain access groups, so the item's
/// access list names both binaries as trusted applications instead. That trust
/// is tied to each binary's code signature, and ad-hoc signatures change with
/// every build: after rebuilding, save the token again from the app.
public enum TokenStore {
    public enum State: Equatable, Sendable {
        case missing
        case saved(String)
        /// A token exists but this binary isn't on its access list, usually after a rebuild.
        case inaccessible

        public var token: String? {
            if case .saved(let token) = self { token } else { nil }
        }
    }

    static let service = "com.dantesmith.ArenaWidget"
    static let account = "are.na-personal-access-token"
    static let label = "Are.na Widget token"

    private static var itemQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    /// Never shows a keychain prompt, so it's safe to call from the widget extension.
    public static func load() -> State {
        var query = itemQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8)?.nonEmpty else {
                return .missing
            }
            return .saved(token)
        case errSecItemNotFound:
            return .missing
        default:
            return .inaccessible
        }
    }

    /// Replaces any saved token. The caller is always trusted; `trustedPaths`
    /// adds other binaries (the widget extension) that may read it without a prompt.
    public static func save(_ token: String, trustedPaths: [String]) throws {
        try delete()

        var trusted: [SecTrustedApplication] = []
        for path in [nil] + trustedPaths.map(Optional.some) {
            var application: SecTrustedApplication?
            let status = SecTrustedApplicationCreateFromPath(path, &application)
            guard status == errSecSuccess, let application else { throw TokenStoreError(status: status) }
            trusted.append(application)
        }

        var access: SecAccess?
        let accessStatus = SecAccessCreate(label as CFString, trusted as CFArray, &access)
        guard accessStatus == errSecSuccess, let access else { throw TokenStoreError(status: accessStatus) }

        var attributes = itemQuery
        attributes[kSecAttrLabel] = label
        attributes[kSecValueData] = Data(token.utf8)
        attributes[kSecAttrAccess] = access
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError(status: status) }
    }

    public static func delete() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TokenStoreError(status: status) }
    }
}

public struct TokenStoreError: LocalizedError, Sendable {
    public let status: OSStatus

    public var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
