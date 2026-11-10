
import Foundation

/// Connects TaskPerfect to Intermedia Exchange Web Services.
final class EWSBackend: TaskBackend {

    private let transport: EWSTransport

    let accountID = UUID()
    let capabilities = BackendCapabilities.exchangeEWS

    init(username: String, password: String) {
        transport = EWSTransport(
            username: username,
            password: password
        )
    }

    // MARK: - Fetch Outlook Tasks

    /// Retrieves real Outlook tasks from Exchange.
    func fetchTasks() async throws -> [TPTask] {
        let response = try await transport.fetchTasks()

        let parser = EWSTaskParser()

        guard let tasks = parser.extractTasks(from: response) else {
            throw TaskBackendError.malformedResponse(
                detail: "Unable to parse Outlook tasks."
            )
        }

        print("Parsed completed tasks:", tasks.filter { $0.status == .completed }.count)
        print("TASKPERFECT DEBUG CHECK 12345")

        let tasksWithIDs = tasks.filter {
            !$0.itemID.isEmpty
        }

        print("Outlook tasks with Exchange IDs: \(tasksWithIDs.count)")
        let uniqueIDs = Set(tasks.map { $0.itemID })

        print("Unique Exchange task IDs: \(uniqueIDs.count)")
        let uniqueTitles = Set(tasks.map { $0.subject })
        print("Unique task titles: \(uniqueTitles.count)")
        print("Total Exchange tasks: \(tasks.count)")

        return tasks
    }

    // MARK: - Task Folders

    /// Initial support for the default Outlook Tasks folder.
    func taskFolders() async throws -> [TPTaskList] {
        return [
            TPTaskList(
                folderID: "tasks",
                displayName: "Tasks",
                isDefault: true
            )
        ]
    }

    // MARK: - Task Synchronization

    /// Initial read-only full snapshot.
    /// Incremental synchronization will be implemented later.
    func changes(
        in folderID: String,
        since token: SyncToken?
    ) async throws -> TaskDelta {

        guard folderID == "tasks" else {
            throw TaskBackendError.itemNotFound(
                itemID: folderID
            )
        }

        var tasks = try await fetchTasks()

        for index in tasks.indices {
            tasks[index].folderID = folderID
        }

        return TaskDelta(
            upserted: tasks,
            deletedItemIDs: [],
            nextToken: SyncToken(rawValue: "ews-read-only-snapshot"),
            isFullResync: true,
            includesLastItemInRange: true
        )
    }

    // MARK: - Read-Only Protection

    /// Creating tasks is disabled during initial testing.
    func create(
        _ task: TPTask,
        in folderID: String
    ) async throws -> TPTask {
        throw TaskBackendError.unsupportedByBackend(
            feature: "Creating Outlook tasks"
        )
    }

    /// Updating tasks is disabled during initial testing.
    func update(_ task: TPTask) async throws -> TPTask {
        throw TaskBackendError.unsupportedByBackend(
            feature: "Updating Outlook tasks"
        )
    }

    /// Deleting tasks is disabled during initial testing.
    func delete(
        itemID: String,
        changeKey: String
    ) async throws {
        throw TaskBackendError.unsupportedByBackend(
            feature: "Deleting Outlook tasks"
        )
    }

    // MARK: - Categories

    /// Actual Exchange categories will be retrieved later.
    func masterCategories() async throws -> [TPCategory] {
        return []
    }

    /// Category changes are disabled during initial testing.
    func saveMasterCategories(
        _ categories: [TPCategory]
    ) async throws {
        throw TaskBackendError.unsupportedByBackend(
            feature: "Saving Outlook categories"
        )
    }

    // MARK: - Connection Verification

    /// Read-only verification of the Outlook Tasks folder.
    func verifyConnection() async throws {
        let response = try await transport.verifyTasksFolder()

        guard let xml = String(
            data: response,
            encoding: .utf8
        ) else {
            throw TaskBackendError.malformedResponse(
                detail: "Unable to decode Exchange response."
            )
        }

        guard xml.contains("ResponseClass=\"Success\"") else {
            throw TaskBackendError.malformedResponse(
                detail: "Exchange did not confirm success."
            )
        }
    }
}
