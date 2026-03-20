import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [Session] = []
    @Published public private(set) var lastSyncAt: Date?

    public let store: SessionStore

    public init(store: SessionStore? = nil) {
        self.store = store ?? SessionStore()
    }

    public var activeSessions: [Session] {
        sessions.filter { [.running, .needsInput, .idle].contains($0.status) }
    }

    public var historySessions: [Session] {
        sessions.filter { [.done, .error].contains($0.status) }
    }

    public var needsInputCount: Int {
        sessions.filter { $0.status == .needsInput }.count
    }

    public var unavailableCount: Int {
        sessions.filter { $0.status == .unavailable }.count
    }

    public func reload() {
        do {
            sessions = try store.listAll()
                .sorted { $0.lastEventAt > $1.lastEventAt }
            lastSyncAt = Date()
        } catch {
            print("[AgentPing] reload failed: \(error)")
            sessions = []
        }
    }

    /// Sync: re-read all session files from disk, then check for dead processes.
    /// Active sessions whose PID is no longer alive are marked as done.
    public func sync() {
        reload()
        markDeadProcessSessions()
    }

    /// Check active sessions for dead processes via kill(pid, 0).
    /// If the process is gone, mark the session as done so it moves to History.
    private func markDeadProcessSessions() {
        var changed = false
        for session in sessions {
            guard [.running, .needsInput, .idle].contains(session.status) else { continue }
            guard let pid = session.pid, pid > 0 else { continue }

            let alive = kill(Int32(pid), 0) == 0 || errno == EPERM
            if !alive {
                var updated = session
                updated.status = .done
                do {
                    try store.write(updated)
                    changed = true
                } catch {
                    print("[AgentPing] failed to mark dead session \(session.id): \(error)")
                }
            }
        }
        if changed {
            reload()
        }
    }

    public func clearUnavailable() {
        do {
            try store.deleteUnavailable()
            reload()
        } catch {
            print("[AgentPing] clearUnavailable failed: \(error)")
        }
    }

    public func clearHistory() {
        do {
            try store.deleteHistory()
            reload()
        } catch {
            print("[AgentPing] clearHistory failed: \(error)")
        }
    }

    public func deleteSession(id: String) {
        do {
            try store.delete(id: id)
            reload()
        } catch {
            print("[AgentPing] deleteSession(\(id)) failed: \(error)")
        }
    }

    /// Remove finished sessions older than 24 hours.
    public func autoPurgeOldSessions() {
        do {
            try store.deleteOlderThan(24 * 60 * 60)
            reload()
        } catch {
            print("[AgentPing] autoPurge failed: \(error)")
        }
    }

    public func markReviewed(id: String) {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        session.reviewedAt = Date()
        updateSession(session)
    }

    public func togglePin(id: String) {
        guard var session = sessions.first(where: { $0.id == id }) else { return }
        session.pinned = !session.pinned
        updateSession(session)
    }

    public var totalCost: Double {
        sessions.compactMap(\.costUsd).reduce(0, +)
    }

    public func updateSession(_ session: Session) {
        do {
            try store.write(session)
            reload()
        } catch {
            print("[AgentPing] updateSession(\(session.id)) failed: \(error)")
        }
    }
}
