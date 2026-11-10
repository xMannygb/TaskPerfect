//
//  EWSTransport.swift
//  TaskPerfect
//
//  Created by Emmanuel Diaz on 10/13/26.
//
import Foundation

/// Handles HTTPS communication with Intermedia Exchange Web Services.
final class EWSTransport: NSObject, URLSessionTaskDelegate {
    
    let endpoint: URL
    let username: String
    private let password: String
    
    init(
        username: String,
        password: String,
        endpoint: URL = URL(
            string: "https://east.exch092.serverdata.net/EWS/Exchange.asmx"
        )!
    ) {
        self.username = username
        self.password = password
        self.endpoint = endpoint
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod

        guard method == NSURLAuthenticationMethodNTLM,
              challenge.protectionSpace.host == endpoint.host,
              challenge.previousFailureCount == 0
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let credential = URLCredential(
            user: username,
            password: password,
            persistence: .none
        )

        completionHandler(.useCredential, credential)
    }

    func sendSOAPRequest(
        _ xml: String,
        action: String
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "text/xml; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "\"http://schemas.microsoft.com/exchange/services/2006/messages/\(action)\"",
            forHTTPHeaderField: "SOAPAction"
        )
        request.httpBody = Data(xml.utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TaskBackendError.malformedResponse(
                detail: "No HTTP response"
            )
        }

        switch http.statusCode {
        case 200:
            return data
        case 401:
            throw TaskBackendError.authenticationFailed
        case 403:
            throw TaskBackendError.ewsDisabledForMailbox
        default:
            throw TaskBackendError.malformedResponse(
                detail: "HTTP \(http.statusCode)"
            )
        }
    }

    func verifyTasksFolder() async throws -> Data {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope
            xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
            xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
            xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
            <soap:Header>
                <t:RequestServerVersion Version="Exchange2016"/>
            </soap:Header>
            <soap:Body>
                <m:GetFolder>
                    <m:FolderShape>
                        <t:BaseShape>Default</t:BaseShape>
                    </m:FolderShape>
                    <m:FolderIds>
                        <t:DistinguishedFolderId Id="tasks"/>
                    </m:FolderIds>
                </m:GetFolder>
            </soap:Body>
        </soap:Envelope>
        """

        return try await sendSOAPRequest(xml, action: "GetFolder")
    }

    // Retrieve tasks from the real Exchange mailbox (read-only).
    func fetchTasks() async throws -> Data {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope
            xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
            xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
            xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
            <soap:Header>
                <t:RequestServerVersion Version="Exchange2016"/>
            </soap:Header>
            <soap:Body>
                <m:FindItem Traversal="Shallow">
                    <m:ItemShape>
                        <t:BaseShape>AllProperties</t:BaseShape>
                    </m:ItemShape>
                    <m:ParentFolderIds>
                        <t:DistinguishedFolderId Id="tasks"/>
                    </m:ParentFolderIds>
                </m:FindItem>
            </soap:Body>
        </soap:Envelope>
        """
        print("EWS FindItem request is being sent")
        let response = try await sendSOAPRequest(xml, action: "FindItem")

        if let responseXML = String(data: response, encoding: .utf8) {
            print("EWS contains Recurrence:", responseXML.contains("<t:Recurrence>"))
            print("EWS contains RecurringMaster:", responseXML.contains("RecurringMaster"))
            print("EWS contains Occurrence:", responseXML.contains("Occurrence"))
            print("EWS Task elements:", responseXML.components(separatedBy: "<t:Task>").count - 1)
            print("EWS contains DueDate:", responseXML.contains("DueDate"))
            print("EWS completed statuses:", responseXML.components(separatedBy: "<t:Status>Completed</t:Status>").count - 1)
            print("EWS not started statuses:", responseXML.components(separatedBy: "<t:Status>NotStarted</t:Status>").count - 1)
        }

        return response
    }

}

