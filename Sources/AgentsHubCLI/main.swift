import ArgumentParser
import AgentsHubCore

struct AgentsHubCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentshub",
        abstract: "AgentsHub CLI - manage Claude Code sessions",
        subcommands: [Report.self, List.self, Status.self]
    )
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Report a session event (called by hooks)")

    @Option(name: .long, help: "Session ID")
    var session: String

    @Option(name: .long, help: "Event type: tool-use, needs-input, stopped, error")
    var event: String

    @Option(name: .long, help: "Task name")
    var name: String?

    @Option(name: .long, help: "Current file")
    var file: String?

    func run() throws {
        let handler = ReportHandler()
        try handler.handle(sessionId: session, event: event, name: name, file: file)
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List active sessions")

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() throws {
        let store = SessionStore()
        let sessions = try store.listAll()

        if json {
            let data = try JSONEncoder.agentsHub.encode(sessions)
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
        let store = SessionStore()
        let sessions = try store.listAll()
        let running = sessions.filter { $0.status == .running }.count
        let needsInput = sessions.filter { $0.status == .needsInput }.count
        let idle = sessions.filter { $0.status == .idle }.count
        print("\(running) running, \(needsInput) needs input, \(idle) idle")
    }
}

AgentsHubCommand.main()
