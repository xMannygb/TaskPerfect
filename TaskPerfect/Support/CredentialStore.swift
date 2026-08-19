import Foundation
import Security

/// Keychain storage for the Exchange password.
///
/// The accessibility class changes with the lock mode, which is the part that
/// actually enforces the setting. Storing the password and then merely *asking*
/// for Face ID in the UI would be theatre — anyone with the device unlocked could
/// read the item directly. Under `.biometric` the Keychain itself refuses to
/// release it without a successful biometric check.
public enum CredentialStore {

    private static var service: String { ServerConfig.keychainService }

    // MARK: Write

    /// Save the password under the protection appropriate to `mode`.
    ///
    /// `.password` mode stores nothing at all — that's what "not remembered"
    /// has to mean if the setting is to be honest.
    @discardableResult
    public static func save(password: String, username: String, mode: AppLockMode) -> Bool {
        delete(username: username)
        guard mode != .password, let data = password.data(using: .utf8) else { return mode == .password }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecValueData as String: data
        ]

        if mode == .biometric {
            // `.biometryCurrentSet` invalidates the item if a face or finger is
            // added or removed — otherwise enrolling a new face would silently
            // grant access to the stored password.
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                nil
            ) else { return false }
            query[kSecAttrAccessControl as String] = access
        } else {
            // Stay signed in: no prompt, but still device-only and never synced
            // to iCloud or included in a backup restored onto another phone.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: Read

    /// Fetch the stored password.
    ///
    /// Under `.biometric` this call is itself the biometric prompt — the system
    /// blocks until Face ID succeeds or fails, so it must not run on the main
    /// thread.
    public static func password(username: String, prompt: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: prompt
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func hasStoredPassword(username: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            // Don't return the data — that would trigger the biometric prompt
            // just to answer "is anything saved?"
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // `interactionNotAllowed` means the item exists but needs authentication,
        // which still answers the question yes.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: Delete

    @discardableResult
    public static func delete(username: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// The remembered username. Not sensitive on its own, and needed to look the
    /// password up, so it lives in `UserDefaults`.
    public static var rememberedUsername: String? {
        get { UserDefaults.standard.string(forKey: "auth.username") }
        set { UserDefaults.standard.set(newValue, forKey: "auth.username") }
    }
}
