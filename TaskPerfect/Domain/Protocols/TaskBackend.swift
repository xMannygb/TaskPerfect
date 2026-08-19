import Foundation

/// The single seam between Task Perfect and any task server.
///
/// Two implementations exist:
///   • `MockBackend` — fixtures, no network. Build the entire UI against this.
///   • `EWSBackend`  — Intermedia Hosted Exchange 2016 over SOAP.
///
/// ⚠️ If a type from `Backend/EWS/` ever appears in `Domain/`, `Features/` or
/// `Persistence/`, the abstraction has leaked. That leak is what makes a future
/// migration expensive, so treat it as a build-breaking bug.
public protocol TaskBackend: Sendable {

    var accountID: UUID { get }
    var capabilities: BackendCapabilities { get }

    /// Cheap round-trip used by account setup to prove credentials and reachability.
    /// Fails fast — do not let this hang behind a long timeout.
    func verifyConnection() async throws

    func taskFolders() async throws -> [TPTaskList]

    /// Incremental sync. Pass `nil` on first run to receive a full snapshot.
    func changes(in folderID: String, since token: SyncToken?) async throws -> TaskDelta

    func create(_ task: TPTask, in folderID: String) async throws -> TPTask

    /// Send the `changeKey` you currently hold. A rejection means the item changed
    /// elsewhere — refetch and resolve rather than retrying blindly.
    func update(_ task: TPTask) async throws -> TPTask

    func delete(itemID: String, changeKey: String) async throws

    /// The mailbox master category list, with colors.
    /// EWS: `GetUserConfiguration` for `CategoryList` in the **calendar** folder.
    func masterCategories() async throws -> [TPCategory]

    /// Replace the master category list wholesale.
    ///
    /// Whole-list rather than per-item on purpose: EWS stores the categories as a
    /// single XML blob inside one hidden folder-associated item, so every change
    /// is a read-modify-write of the entire thing. Modeling it as "add one
    /// category" would hide a clobber risk that the caller needs to see.
    ///
    /// Implementations must preserve each category's `guid` — desktop Outlook
    /// treats a changed GUID as a different category.
    func saveMasterCategories(_ categories: [TPCategory]) async throws
}

// MARK: - Capabilities

/// What the connected server can actually store.
///
/// EWS supports the complete Outlook task item. Microsoft Graph's To Do API does not —
/// it drops percent complete, effort tracking, mileage, billing and companies. If
/// Intermedia ever migrates you to Microsoft 365, these flags are what stop the app
/// from silently discarding user data.
public struct BackendCapabilities: Hashable, Sendable {

    public var supportsPercentComplete: Bool
    public var supportsEffortTracking: Bool      // totalWork / actualWork
    public var supportsMileageAndBilling: Bool
    public var supportsCompanies: Bool
    public var supportsSensitivity: Bool
    public var supportsRichTextBody: Bool
    public var supportsRecurrence: Bool
    public var supportsRegeneratingRecurrence: Bool
    public var supportsMultipleFolders: Bool
    public var supportsServerSideSearch: Bool
    /// Whether the category list itself can be edited, not just applied.
    public var supportsCategoryManagement: Bool

    public init(
        supportsPercentComplete: Bool = true,
        supportsEffortTracking: Bool = true,
        supportsMileageAndBilling: Bool = true,
        supportsCompanies: Bool = true,
        supportsSensitivity: Bool = true,
        supportsRichTextBody: Bool = true,
        supportsRecurrence: Bool = true,
        supportsRegeneratingRecurrence: Bool = true,
        supportsMultipleFolders: Bool = true,
        supportsServerSideSearch: Bool = true,
        supportsCategoryManagement: Bool = true
    ) {
        self.supportsPercentComplete = supportsPercentComplete
        self.supportsEffortTracking = supportsEffortTracking
        self.supportsMileageAndBilling = supportsMileageAndBilling
        self.supportsCompanies = supportsCompanies
        self.supportsSensitivity = supportsSensitivity
        self.supportsRichTextBody = supportsRichTextBody
        self.supportsRecurrence = supportsRecurrence
        self.supportsRegeneratingRecurrence = supportsRegeneratingRecurrence
        self.supportsMultipleFolders = supportsMultipleFolders
        self.supportsServerSideSearch = supportsServerSideSearch
        self.supportsCategoryManagement = supportsCategoryManagement
    }

    /// Exchange 2016 via EWS — everything.
    public static let exchangeEWS = BackendCapabilities()

    /// Reserved for a future Microsoft 365 migration. Bind field visibility in
    /// TaskDetail to these flags now and that migration costs you nothing later.
    public static let microsoftGraphToDo = BackendCapabilities(
        supportsPercentComplete: false,
        supportsEffortTracking: false,
        supportsMileageAndBilling: false,
        supportsCompanies: false,
        supportsSensitivity: false,
        supportsRegeneratingRecurrence: false,
        supportsServerSideSearch: false
    )
}

// MARK: - Errors

public enum TaskBackendError: LocalizedError, Sendable {
    case notConfigured
    case duplicateCategory(name: String)
    case authenticationFailed
    /// 403, or a SOAP fault indicating EWS is switched off for this mailbox plan.
    case ewsDisabledForMailbox
    case networkUnavailable
    case serverUnreachable(host: String)
    /// The `changeKey` you sent was stale — someone edited elsewhere.
    case conflict(itemID: String)
    case itemNotFound(itemID: String)
    case syncStateInvalid
    case malformedResponse(detail: String)
    case soapFault(code: String, message: String)
    case unsupportedByBackend(feature: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No account is set up yet."
        case .duplicateCategory(let name):
            return "A category named \"\(name)\" already exists."
        case .authenticationFailed:
            return "That username or password wasn't accepted. Check that your username includes the domain."
        case .ewsDisabledForMailbox:
            return "This mailbox can't use Exchange Web Services. Your provider may need to enable it."
        case .networkUnavailable:
            return "No network connection."
        case .serverUnreachable(let host):
            return "Couldn't reach \(host)."
        case .conflict:
            return "This task was changed somewhere else. Refreshing to get the latest version."
        case .itemNotFound:
            return "That task no longer exists on the server."
        case .syncStateInvalid:
            return "Sync needs to start over. Your tasks will reload."
        case .malformedResponse(let detail):
            return "Unexpected response from the server. (\(detail))"
        case .soapFault(_, let message):
            return "The server reported an error: \(message)"
        case .unsupportedByBackend(let feature):
            return "\(feature) isn't supported by this account type."
        }
    }

    /// Whether `ChangeQueue` should retry with backoff rather than surfacing to the user.
    public var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .serverUnreachable, .conflict, .syncStateInvalid:
            return true
        case .notConfigured, .duplicateCategory, .authenticationFailed, .ewsDisabledForMailbox,
             .itemNotFound, .malformedResponse, .soapFault, .unsupportedByBackend:
            return false
        }
    }
}
