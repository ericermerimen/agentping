import Foundation

public final class APIRouter {
    private let store: SessionStore
    private let version: String
    public var port: UInt16 = 0

    public init(store: SessionStore, version: String = "0.6.0") {
        self.store = store
        self.version = version
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        // Route matching
        let path = request.path
        let components = path.split(separator: "?", maxSplits: 1)
        let cleanPath = String(components[0])
        let queryString = components.count > 1 ? String(components[1]) : nil

        // /v1/health
        if cleanPath == "/v1/health" {
            guard request.method == .GET else { return .methodNotAllowed }
            return handleHealth()
        }

        // /v1/report
        if cleanPath == "/v1/report" {
            guard request.method == .POST else { return .methodNotAllowed }
            return handleReport(request)
        }

        // /v1/sessions
        if cleanPath == "/v1/sessions" {
            guard request.method == .GET else { return .methodNotAllowed }
            return handleListSessions(query: queryString)
        }

        // /v1/sessions/:id
        if cleanPath.hasPrefix("/v1/sessions/") {
            let id = String(cleanPath.dropFirst("/v1/sessions/".count))
            guard !id.isEmpty else { return .notFound }
            // Reject IDs with path traversal characters
            guard !id.contains("/"), !id.contains("\\"), !id.contains("..") else {
                return .error(400, "Bad Request", "session ID contains invalid characters")
            }
            switch request.method {
            case .GET:    return handleGetSession(id: id)
            case .DELETE: return handleDeleteSession(id: id)
            default:      return .methodNotAllowed
            }
        }

        return .notFound
    }

    // MARK: - Handlers

    private func handleHealth() -> HTTPResponse {
        return .json(200, "OK", ["status": "ok", "version": version, "port": port])
    }

    private func handleReport(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .error(400, "Bad Request", "Invalid JSON body")
        }

        guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else {
            return .error(400, "Bad Request", "session_id is required")
        }
        // Reject session IDs with path traversal characters
        guard !sessionId.contains("/"), !sessionId.contains("\\"), !sessionId.contains("..") else {
            return .error(400, "Bad Request", "session_id contains invalid characters")
        }
        guard let event = json["event"] as? String, !event.isEmpty else {
            return .error(400, "Bad Request", "event is required")
        }

        do {
            var session = (try? store.read(id: sessionId)) ?? Session(id: sessionId)

            // Update fields from payload
            if let name = json["name"] as? String, session.name == nil {
                session.name = name
            }
            if let cwd = json["cwd"] as? String {
                session.cwd = cwd
                if session.name == nil {
                    session.name = URL(fileURLWithPath: cwd).lastPathComponent
                }
            }
            if let file = json["file"] as? String { session.file = file }
            if let app = json["app"] as? String { session.app = app }
            if let transcriptPath = json["transcript_path"] as? String {
                session.transcriptPath = transcriptPath
                // Extract task description and context % from transcript (same as ReportHandler)
                if let taskDesc = ReportHandler.extractLastMessage(from: transcriptPath) {
                    session.taskDescription = taskDesc
                }
                // Prefer context_percent from hook stdin (authoritative), fall back to transcript parsing
                if json["context_percent"] == nil {
                    session.contextPercent = ReportHandler.readContextPercent(transcriptPath: transcriptPath)
                }
                // Auto-extract provider/model from Claude transcripts
                if session.provider == nil, session.model == nil,
                   let modelId = ReportHandler.readModelFromTranscript(transcriptPath),
                   !modelId.hasPrefix("<") {
                    let (provider, model) = ReportHandler.humanizeModelName(modelId)
                    session.provider = provider
                    session.model = model
                }
                // Calculate cost from token usage (unless explicit cost_usd is provided)
                if json["cost_usd"] == nil {
                    session.costUsd = ReportHandler.readCostFromTranscript(transcriptPath) ?? session.costUsd
                }
            }
            if let provider = json["provider"] as? String { session.provider = provider }
            if let model = json["model"] as? String { session.model = model }
            if let pid = json["pid"] as? Int { session.pid = pid }
            if let costUsd = json["cost_usd"] as? Double { session.costUsd = costUsd }
            if let contextPct = json["context_percent"] as? Double { session.contextPercent = contextPct }

            session.status = SessionStatus.from(event: event, current: session.status)

            session.lastEventAt = Date()
            try store.write(session)

            let data = try JSONEncoder.agentPing.encode(session)
            return HTTPResponse(status: 200, statusText: "OK", body: data)
        } catch {
            return .error(500, "Internal Server Error", error.localizedDescription)
        }
    }

    private func handleListSessions(query: String?) -> HTTPResponse {
        do {
            var sessions = try store.listAll()
                .sorted { $0.lastEventAt > $1.lastEventAt }

            // Filter by status if query param present
            if let query, let statusFilter = parseQuery(query)["status"],
               let status = SessionStatus(rawValue: statusFilter) {
                sessions = sessions.filter { $0.status == status }
            }

            let data = try JSONEncoder.agentPing.encode(sessions)
            return HTTPResponse(status: 200, statusText: "OK", body: data)
        } catch {
            return .error(500, "Internal Server Error", error.localizedDescription)
        }
    }

    private func handleGetSession(id: String) -> HTTPResponse {
        do {
            guard let session = try store.read(id: id) else {
                return .error(404, "Not Found", "Session not found")
            }
            let data = try JSONEncoder.agentPing.encode(session)
            return HTTPResponse(status: 200, statusText: "OK", body: data)
        } catch {
            return .error(500, "Internal Server Error", error.localizedDescription)
        }
    }

    private func handleDeleteSession(id: String) -> HTTPResponse {
        do {
            guard try store.read(id: id) != nil else {
                return .error(404, "Not Found", "Session not found")
            }
            try store.delete(id: id)
            return HTTPResponse(status: 204, statusText: "No Content", body: nil)
        } catch {
            return .error(500, "Internal Server Error", error.localizedDescription)
        }
    }

    private func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }
}
