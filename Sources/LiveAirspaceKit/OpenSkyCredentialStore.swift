import Foundation
import Security

/// Keeps the user's OpenSky API client in the keychain. Nothing is stored in the app bundle or the repository.
public enum OpenSkyCredentialStore {
    public static let defaultService = "com.bureau.liveairspace.opensky"

    private static func base(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    @discardableResult
    public static func save(_ credentials: OpenSkyCredentials, service: String = defaultService) -> Bool {
        remove(service: service)
        var q = base(service)
        q[kSecAttrAccount as String] = credentials.clientID
        q[kSecValueData as String] = Data(credentials.clientSecret.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public static func load(service: String = defaultService) -> OpenSkyCredentials? {
        var q = base(service)
        q[kSecReturnData as String] = true
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let item = out as? [String: Any],
              let id = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let secret = String(data: data, encoding: .utf8) else { return nil }
        return OpenSkyCredentials(clientID: id, clientSecret: secret)
    }

    public static func remove(service: String = defaultService) {
        SecItemDelete(base(service) as CFDictionary)
    }
}
