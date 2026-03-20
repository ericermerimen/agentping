import Foundation

public final class SessionStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentping/sessions")
    }

    private func filePath(for id: String) -> URL {
        directory.appendingPathComponent("\(Self.sanitizeId(id)).json")
    }

    /// Sanitize a session ID to prevent path traversal attacks.
    /// Strips path separators and ".." segments so IDs always resolve within the sessions directory.
    static func sanitizeId(_ id: String) -> String {
        // Remove any path separator characters and null bytes
        var clean = id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\0", with: "")
        // Collapse ".." to prevent traversal
        while clean.contains("..") {
            clean = clean.replacingOccurrences(of: "..", with: "_")
        }
        // Ensure non-empty
        if clean.isEmpty { clean = "_invalid_" }
        return clean
    }

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // Restrict session directory to owner-only (0700)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    public func write(_ session: Session) throws {
        try ensureDirectory()
        let data = try JSONEncoder.agentPing.encode(session)
        try data.write(to: filePath(for: session.id), options: .atomic)
    }

    public func read(id: String) throws -> Session? {
        let path = filePath(for: id)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try JSONDecoder.agentPing.decode(Session.self, from: data)
    }

    public func listAll() throws -> [Session] {
        try ensureDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            do {
                return try JSONDecoder.agentPing.decode(Session.self, from: data)
            } catch {
                print("[AgentPing] failed to decode \(url.lastPathComponent): \(error)")
                return nil
            }
        }
    }

    public func delete(id: String) throws {
        let path = filePath(for: id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    @discardableResult
    public func deleteUnavailable() throws -> Int {
        let sessions = try listAll()
        var count = 0
        for session in sessions where session.status == .unavailable {
            try delete(id: session.id)
            count += 1
        }
        return count
    }

    /// Delete all sessions with done/error status.
    @discardableResult
    public func deleteHistory() throws -> Int {
        let sessions = try listAll()
        var count = 0
        for session in sessions where session.status == .done || session.status == .error {
            try delete(id: session.id)
            count += 1
        }
        return count
    }

    /// Delete sessions older than the given interval.
    @discardableResult
    public func deleteOlderThan(_ interval: TimeInterval) throws -> Int {
        let sessions = try listAll()
        let cutoff = Date().addingTimeInterval(-interval)
        var count = 0
        for session in sessions where session.lastEventAt < cutoff {
            // Only auto-purge finished sessions
            guard session.status == .done || session.status == .error || session.status == .unavailable else { continue }
            try delete(id: session.id)
            count += 1
        }
        return count
    }
}
