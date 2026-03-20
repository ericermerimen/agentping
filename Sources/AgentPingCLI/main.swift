import Foundation
import ArgumentParser
import AgentPingCore

/// Lightweight HTTP client for talking to the AgentPing API server.
enum APIClient {
    static let timeout: TimeInterval = 2.0

    /// Try to reach the local API server. Returns (data, statusCode) or nil if unreachable.
    static func request(_ method: String, _ path: String, body: Data? = nil) -> (Data, Int)? {
        let port = APIServer.readPort() ?? 19199
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(path)") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = timeout
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data, Int)?

        URLSession.shared.dataTask(with: req) { data, response, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let data,
                  let httpResponse = response as? HTTPURLResponse else { return }
            result = (data, httpResponse.statusCode)
        }.resume()

        semaphore.wait()
        return result
    }

    /// POST a report to the API. Returns true if successful.
    static func report(_ payload: [String: Any]) -> Bool {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        guard let (_, status) = request("POST", "v1/report", body: body) else { return false }
        return status == 200
    }
}

struct AgentPingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentping",
        abstract: "AgentPing CLI - manage Claude Code sessions",
        subcommands: [Report.self, List.self, Status.self, Clear.self, Delete.self]
    )
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Report a session event (called by hooks)")

    @Option(name: .long, help: "Session ID")
    var session: String?

    @Option(name: .long, help: "Event type: tool-use, needs-input, stopped, error")
    var event: String

    @Option(name: .long, help: "Task name")
    var name: String?

    @Option(name: .long, help: "Current file")
    var file: String?

    /// JSON payload from stdin (Claude Code hooks pass session data here)
    private struct StdinPayload: Decodable {
        let session_id: String?
        let cwd: String?
        let transcript_path: String?
        let context_window: ContextWindow?

        struct ContextWindow: Decodable {
            let used_percentage: Double?
        }
    }

    /// Map TERM_PROGRAM env var to a display name
    private static func detectApp() -> String? {
        guard let term = ProcessInfo.processInfo.environment["TERM_PROGRAM"] else { return nil }
        switch term.lowercased() {
        case "ghostty":                return "Ghostty"
        case "vscode":                 return "VSCode"
        case "iterm.app":              return "iTerm"
        case "apple_terminal":         return "Terminal"
        case "warpterminal":           return "Warp"
        case "alacritty":              return "Alacritty"
        case "kitty":                  return "kitty"
        case "wezterm":                return "WezTerm"
        case "tmux":                   return "tmux"
        default:                       return term
        }
    }

    /// Walk up the process tree to find the Claude Code (node) process PID.
    /// Hook execution chain: claude (node) → shell → agentping report
    private static func detectClaudePid() -> Int {
        var pid = Int(getppid()) // parent of this process (shell)
        for _ in 0..<5 {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let ppid = Int(info.kp_eproc.e_ppid)
            if ppid <= 1 { break }
            // Return the first ancestor that looks like a long-running process
            // (the shell's parent, which is the Claude Code node process)
            pid = ppid
            break
        }
        return pid
    }

    private func readStdinPayload() -> StdinPayload? {
        let data = FileHandle.standardInput.availableData
        guard !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(StdinPayload.self, from: data)
    }

    func run() throws {
        let stdin = readStdinPayload()
        guard let sessionId = session ?? stdin?.session_id else {
            throw ValidationError("Session ID is required via --session or stdin JSON")
        }

        // Build API payload
        var payload: [String: Any] = [
            "session_id": sessionId,
            "event": event,
        ]
        if let name { payload["name"] = name }
        if let file { payload["file"] = file }
        if let cwd = stdin?.cwd { payload["cwd"] = cwd }
        if let transcriptPath = stdin?.transcript_path { payload["transcript_path"] = transcriptPath }
        if let contextPct = stdin?.context_window?.used_percentage {
            payload["context_percent"] = contextPct / 100.0 // API expects 0.0-1.0
        }
        if let app = Self.detectApp() { payload["app"] = app }
        // Auto-detect the Claude Code process PID (grandparent of this hook process)
        payload["pid"] = Self.detectClaudePid()

        // Try HTTP API first
        if APIClient.report(payload) {
            return
        }

        // Fallback to direct file write
        let handler = ReportHandler()
        try handler.handle(
            sessionId: sessionId,
            event: event,
            name: name,
            file: file,
            cwd: stdin?.cwd,
            transcriptPath: stdin?.transcript_path,
            app: Self.detectApp(),
            contextPercent: stdin?.context_window?.used_percentage.map { $0 / 100.0 }
        )
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List active sessions")

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        // Try HTTP API first
        if let (data, status) = APIClient.request("GET", "v1/sessions"), status == 200 {
            if json {
                print(String(data: data, encoding: .utf8) ?? "[]")
            } else {
                let sessions = try JSONDecoder.agentPing.decode([Session].self, from: data)
                for s in sessions {
                    let name = s.name ?? "unnamed"
                    let app = s.app ?? "unknown"
                    let model = [s.provider, s.model].compactMap { $0 }.joined(separator: " ")
                    let modelSuffix = model.isEmpty ? "" : " [\(model)]"
                    print("[\(s.status.rawValue)] \(name) (\(app))\(modelSuffix)")
                }
            }
            return
        }

        // Fallback to direct file read
        let store = SessionStore()
        let sessions = try store.listAll()
        if json {
            let data = try JSONEncoder.agentPing.encode(sessions)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            for s in sessions {
                let name = s.name ?? "unnamed"
                let app = s.app ?? "unknown"
                print("[\(s.status.rawValue)] \(name) (\(app))")
            }
        }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "One-line status summary")

    func run() throws {
        let sessions: [Session]

        if let (data, status) = APIClient.request("GET", "v1/sessions"), status == 200,
           let decoded = try? JSONDecoder.agentPing.decode([Session].self, from: data) {
            sessions = decoded
        } else {
            sessions = try SessionStore().listAll()
        }

        let running = sessions.filter { $0.status == .running }.count
        let needsInput = sessions.filter { $0.status == .needsInput }.count
        let idle = sessions.filter { $0.status == .idle }.count
        print("\(running) running, \(needsInput) needs input, \(idle) idle")
    }
}

struct Clear: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clear finished sessions from history")

    @Flag(name: .long, help: "Clear all history (done + error)")
    var all = false

    @Option(name: .long, help: "Clear sessions older than N hours")
    var olderThan: Int?

    func run() throws {
        let store = SessionStore()
        if let hours = olderThan {
            let count = try store.deleteOlderThan(Double(hours) * 3600)
            print("Cleared \(count) sessions older than \(hours)h")
        } else if all {
            let count = try store.deleteHistory()
            print("Cleared \(count) history sessions")
        } else {
            let count = try store.deleteUnavailable()
            print("Cleared \(count) unavailable sessions")
        }
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a specific session")

    @Argument(help: "Session ID to delete")
    var sessionId: String

    func run() throws {
        if let (_, status) = APIClient.request("DELETE", "v1/sessions/\(sessionId)") {
            if status == 204 || status == 200 {
                print("Deleted session \(sessionId)")
                return
            }
        }

        // Fallback
        let store = SessionStore()
        try store.delete(id: sessionId)
        print("Deleted session \(sessionId)")
    }
}

AgentPingCommand.main()
