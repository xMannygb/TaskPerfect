import Foundation

/// Connection settings for this organization's Intermedia Hosted Exchange.
///
/// The defaults are baked in, because the app is distributed internally and asking
/// every colleague to type a server address is a way to collect typos. But they're
/// editable: Intermedia occasionally moves mailboxes between hosts, and a hardcoded
/// address would mean shipping a new build to recover from that.
///
/// Stored in `UserDefaults` rather than the Keychain — a server name isn't a secret,
/// and it has to be readable before anyone has signed in.
public enum ServerConfig {

    public static let defaultServerHost = "east.exch092.serverdata.net"
    public static let defaultDomain     = "EXCH092"

    private enum Keys {
        static let host = "server.host"
        static let domain = "server.domain"
    }

    public static var serverHost: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.host)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false ? stored! : defaultServerHost)
        }
        set {
            let cleaned = normalizedHost(newValue)
            UserDefaults.standard.set(cleaned, forKey: Keys.host)
        }
    }

    /// Optional. Signing in with a full e-mail address authenticates without it,
    /// which is how the mailbox is actually reached in practice — so an empty
    /// value is a legitimate setting rather than a missing one.
    public static var domain: String {
        get { UserDefaults.standard.string(forKey: Keys.domain) ?? defaultDomain }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.domain
            )
        }
    }

    /// True when either value has been changed from the shipped default.
    public static var isCustomized: Bool {
        serverHost != defaultServerHost || domain != defaultDomain
    }

    public static func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.host)
        UserDefaults.standard.removeObject(forKey: Keys.domain)
    }

    /// Strip what people paste in. A host typed as a full URL, or with a trailing
    /// slash or an `/EWS/Exchange.asmx` path, is the common mistake — and it fails
    /// with a confusing error rather than an obviously wrong address.
    public static func normalizedHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value
    }

    public static var ewsEndpoint: URL {
        URL(string: "https://\(serverHost)/EWS/Exchange.asmx")
            ?? URL(string: "https://\(defaultServerHost)/EWS/Exchange.asmx")!
    }

    /// Exchange 2016. Fall back to `Exchange2013_SP1` if the server rejects this.
    public static let schemaVersion = "Exchange2016"

    /// Domain-qualified form Exchange expects for Basic/NTLM auth.
    public static func qualifiedUsername(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Already qualified as DOMAIN\user or user@domain — leave it alone.
        guard !trimmed.contains("\\"), !trimmed.contains("@") else { return trimmed }
        // Domain is optional: with it blank, send the bare username rather than
        // a leading backslash, which Exchange rejects.
        let dom = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        return dom.isEmpty ? trimmed : "\(dom)\\\(trimmed)"
    }

    /// Keychain service identifier. Change the bundle prefix to match your app.
    public static let keychainService = "com.yourorg.taskperfect.credentials"

    /// Network timeouts. Account setup should fail fast so users aren't left staring
    /// at a spinner when they've typed the wrong password.
    public static let verifyTimeout: TimeInterval = 15
    public static let requestTimeout: TimeInterval = 45
}
