
import Foundation

final class EWSTaskParser: NSObject, XMLParserDelegate {

    private var taskCount = 0
    private var taskTitles: [String] = []
    private var parsedTasks: [TPTask] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentItemID = ""
    private var currentChangeKey = ""
    private var currentStatus = ""
    private var currentDueDate = ""
    private var isInsideTask = false

    // MARK: - Public Parsing Methods

    func extractTitles(from data: Data) -> [String]? {
        reset()

        let parser = XMLParser(data: data)
        parser.delegate = self

        return parser.parse() ? taskTitles : nil
    }

    func extractTasks(from data: Data) -> [TPTask]? {
        reset()

        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse() else {
            return nil
        }

        return parsedTasks
    }

    func countTasks(in data: Data) -> Int? {
        reset()

        let parser = XMLParser(data: data)
        parser.delegate = self

        return parser.parse() ? taskCount : nil
    }

    // MARK: - Reset

    private func reset() {
        taskCount = 0
        taskTitles = []
        parsedTasks = []

        currentElement = ""
        currentTitle = ""
        currentItemID = ""
        currentChangeKey = ""
        currentDueDate = ""
        isInsideTask = false
    }

    // MARK: - XML Parsing

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)
            ?? elementName

        if name == "Task" {
            isInsideTask = true
            currentElement = ""
            currentTitle = ""
            currentItemID = ""
            currentChangeKey = ""
            currentStatus = ""
            currentDueDate = ""
        }

        if isInsideTask && name == "ItemId" {
            currentItemID = attributeDict["Id"] ?? ""
            currentChangeKey = attributeDict["ChangeKey"] ?? ""
        }

        if isInsideTask && name == "Subject" {
            currentElement = "Subject"
        }
        
        if isInsideTask && name == "Status" {
            currentElement = "Status"
        }
        
        if isInsideTask && name == "DueDate" {
            currentElement = "DueDate"
        }
    }

    func parser(
        _ parser: XMLParser,
        foundCharacters string: String
    ) {
        if isInsideTask && currentElement == "Subject" {
            currentTitle += string
        }

        if isInsideTask && currentElement == "Status" {
            currentStatus += string
        }
        
        if isInsideTask && currentElement == "DueDate" {
            currentDueDate += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.split(separator: ":").last.map(String.init)
            ?? elementName

        if name == "Subject" && isInsideTask {
            currentElement = ""
        }
        
        if name == "Status" && isInsideTask {
            currentElement = ""
        }
        
        if name == "DueDate" && isInsideTask {
            currentElement = ""
        }

        if name == "Task" && isInsideTask {
            taskCount += 1

            let title = currentTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            taskTitles.append(title)
            
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let dueDate = dateFormatter.date(from: currentDueDate)
                ?? ISO8601DateFormatter().date(from: currentDueDate)
            
            var task = TPTask(
                subject: title,
                dueDate: dueDate,
                status: currentStatus == "Completed" ? .completed : .notStarted,
                percentComplete: currentStatus == "Completed" ? 100 : 0
            )
            
            task.itemID = currentItemID
            task.changeKey = currentChangeKey

            parsedTasks.append(task)
            if let dueDate = task.dueDate {
                print("Parsed task due date:", dueDate)
            }

            // Critical: finish the current task before parsing the next.
            isInsideTask = false
            currentElement = ""
        }
    }
}
