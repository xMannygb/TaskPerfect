import Foundation
import LocalAuthentication

/// How the app is unlocked when it's reopened.
///
/// **One picker, not two toggles.** The three states are mutually exclusive by
/// nature — "stay signed in" and "require Face ID" are contradictory instructions
/// — and separate switches would need coordination logic to stop them fighting.
/// An enum makes the conflict impossible to express rather than merely handled.
public enum AppLockMode: String, CaseIterable, Codable, Sendable {
    /// Sign in with the Exchange password each time. Nothing is remembered.
    case password
    /// Credentials stay in the Keychain, released only after a successful
    /// biometric check.
    case biometric
    /// Credentials stay in the Keychain and the app opens straight to the list.
    case staySignedIn

    public var label: String {
        switch self {
        case .password:     return "Password every time"
        case .biometric:    return AppLock.biometryName
        case .staySignedIn: return "Stay signed in"
        }
    }

    public var explanation: String {
        switch self {
        case .password:
            return "Your password isn't stored. You'll sign in each time the app opens."
        case .biometric:
            return "Your password is kept in the iPhone's Keychain and released only after \(AppLock.biometryName) succeeds."
        case .staySignedIn:
            return "The app opens straight to your tasks. Anyone who can unlock this iPhone can read them."
        }
    }
}

public enum AppLock {

    // MARK: Availability

    /// Whether this device can do Face ID or Touch ID *right now* — the hardware
    /// exists and something is actually enrolled. Both matter: a device with a
    /// Face ID sensor but no face registered can't authenticate, and offering the
    /// option would strand the user outside their own tasks.
    public static var biometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// "Face ID", "Touch ID", or "Biometrics" — never hardcode one. An iPhone SE
    /// user being told to use Face ID has been given a wrong instruction.
    public static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "Biometrics"
        }
    }

    /// Modes this device can actually offer.
    public static var availableModes: [AppLockMode] {
        AppLockMode.allCases.filter { $0 != .biometric || biometryAvailable }
    }

    // MARK: Unlocking

    public enum UnlockResult: Sendable {
        case success
        /// User cancelled, or biometry failed and they backed out. Stay locked.
        case cancelled
        /// Biometry is unusable — enrollment changed, or too many failures.
        /// The caller falls back to the password screen rather than locking the
        /// user out of their own mailbox.
        case unavailable(reason: String)
    }

    /// Prompt for biometrics.
    ///
    /// Uses `.deviceOwnerAuthentication`, not `...WithBiometrics`, so the system
    /// offers the device passcode when a face isn't recognized. Without that
    /// fallback, a user in sunglasses is locked out with no way forward.
    public static func unlock(reason: String = "Unlock Task Perfect") async -> UnlockResult {
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(reason: error?.localizedDescription ?? "Not available")
        }

        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .cancelled
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .userFallback:
                // They tapped "Use Password" — send them to the sign-in screen.
                return .unavailable(reason: "Password requested")
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                return .unavailable(reason: laError.localizedDescription)
            default:
                return .cancelled
            }
        } catch {
            return .cancelled
        }
    }
}
