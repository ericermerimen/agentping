import Foundation

public final class ReportHandler {
    private let store: SessionStore

    public init(store: SessionStore? = nil) {
        self.store = store ?? SessionStore()
    }

    public func handle(sessionId: String, event: String, name: String?, file: String?) throws {
        var session = try store.read(id: sessionId) ?? Session(id: sessionId)

        // Update name only if provided and not already set
        if let name, session.name == nil {
            session.name = name
        }

        // Update file if provided
        if let file {
            session.file = file
        }

        // Map event to status
        switch event {
        case "tool-use":
            session.status = .running
        case "needs-input":
            session.status = .needsInput
        case "stopped":
            session.status = .done
        case "error":
            session.status = .error
        default:
            session.status = .running
        }

        session.lastEventAt = Date()
        try store.write(session)
    }
}
