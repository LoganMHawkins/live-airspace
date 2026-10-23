import Foundation
import Security

/// Passes the current airspace from the app to the Top Shelf extension through a shared keychain group
/// (works with a team wildcard provisioning profile, unlike App Groups which need explicit portal registration).
public enum SharedConfig {
    private static let service = "com.bureau.liveairspace.config"

    /// `Info.plist` carries `AppIdentifierPrefix` (build setting), e.g. "ABCDE12345.".
    private static func accessGroup(_ bundle: Bundle) -> String? {
        (bundle.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String).map { $0 + "com.bureau.liveairspace.shared" }
    }

    private static func query(_ bundle: Bundle) -> [String: Any]? {
        guard let group = accessGroup(bundle), !group.contains("$(") else { return nil }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "config", kSecAttrAccessGroup as String: group]
    }

    public static func save(_ config: AirspaceConfig, bundle: Bundle = .main) {
        guard var q = query(bundle), let data = try? JSONEncoder().encode(config) else { return }
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    public static func load(bundle: Bundle = .main) -> AirspaceConfig? {
        guard var q = query(bundle) else { return nil }
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AirspaceConfig.self, from: data)
    }
}
