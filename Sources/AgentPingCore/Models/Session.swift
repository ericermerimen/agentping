import Foundation

public enum SessionStatus: String, Codable, CaseIterable {
    case running
    case needsInput = "needs-input"
    case idle
    case done
    case error
    case unavailable

    /// Map a hook event name to a session status.
    /// "stopped" won't downgrade "needs-input" because both hooks fire and Stop comes last.
    /// "subagent-stop" preserves current status to avoid overwriting idle after background agents finish.
    public static func from(event: String, current: SessionStatus) -> SessionStatus {
        switch event {
        case "tool-use":      return .running
        case "needs-input":   return .needsInput
        case "stopped":       return current == .needsInput ? .needsInput : .idle
        case "session-end":   return .done
        case "error":         return .error
        case "subagent-stop": return current
        default:              return .running
        }
    }
}

public struct Session: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String?
    public var status: SessionStatus
    public var app: String?
    public var pid: Int?
    public var windowId: Int?
    public var cwd: String?
    public var file: String?
    public var startedAt: Date
    public var lastEventAt: Date
    public var notifications: Bool
    public var costUsd: Double?
    public var transcriptPath: String?
    public var taskDescription: String?
    public var contextPercent: Double?
    public var pinned: Bool
    public var provider: String?
    public var model: String?
    public var reviewedAt: Date?

    /// Whether this idle session hasn't been reviewed by the user yet.
    public var isFreshIdle: Bool {
        guard status == .idle else { return false }
        guard let reviewed = reviewedAt else { return true }
        return reviewed < lastEventAt
    }

    public init(
        id: String,
        name: String? = nil,
        status: SessionStatus = .running,
        app: String? = nil,
        pid: Int? = nil,
        windowId: Int? = nil,
        cwd: String? = nil,
        file: String? = nil,
        startedAt: Date = Date(),
        lastEventAt: Date = Date(),
        notifications: Bool = true,
        costUsd: Double? = nil,
        transcriptPath: String? = nil,
        taskDescription: String? = nil,
        contextPercent: Double? = nil,
        pinned: Bool = false,
        provider: String? = nil,
        model: String? = nil,
        reviewedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.app = app
        self.pid = pid
        self.windowId = windowId
        self.cwd = cwd
        self.file = file
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.notifications = notifications
        self.costUsd = costUsd
        self.transcriptPath = transcriptPath
        self.taskDescription = taskDescription
        self.contextPercent = contextPercent
        self.pinned = pinned
        self.provider = provider
        self.model = model
        self.reviewedAt = reviewedAt
    }
}

// Custom decoding to handle backward compatibility (pinned may not exist in old JSON)
extension Session {
    enum CodingKeys: String, CodingKey {
        case id, name, status, app, pid, windowId, cwd, file
        case startedAt, lastEventAt, notifications, costUsd
        case transcriptPath, taskDescription, contextPercent, pinned
        case provider, model, reviewedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        status = try container.decode(SessionStatus.self, forKey: .status)
        app = try container.decodeIfPresent(String.self, forKey: .app)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        windowId = try container.decodeIfPresent(Int.self, forKey: .windowId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        lastEventAt = try container.decode(Date.self, forKey: .lastEventAt)
        notifications = try container.decode(Bool.self, forKey: .notifications)
        costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        taskDescription = try container.decodeIfPresent(String.self, forKey: .taskDescription)
        contextPercent = try container.decodeIfPresent(Double.self, forKey: .contextPercent)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
    }
}

// MARK: - Display helpers

extension Session {
    public var isAttention: Bool {
        status == .needsInput || status == .error || isFreshIdle
    }

    public var isHomeCwd: Bool {
        guard let cwd = cwd else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd == home || cwd == home + "/"
    }

    public var projectName: String {
        if let cwd = cwd, !cwd.isEmpty, !isHomeCwd {
            let last = URL(fileURLWithPath: cwd).lastPathComponent
            if !last.isEmpty { return last }
        }
        if let task = taskDescription, !task.isEmpty {
            return task
        }
        return name ?? "Unnamed"
    }

    public var displayPath: String {
        guard let cwd = cwd, !cwd.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    public var subtitle: String? {
        if isHomeCwd { return "~" }
        if let task = taskDescription, !task.isEmpty, !isHomeCwd {
            return task
        }
        return displayPath.isEmpty ? nil : displayPath
    }

    /// Formatted idle duration relative to `now`. Shared by ExpandedRowView and CompactRowView.
    public func idleElapsed(now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(lastEventAt)))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "idle \(h)h" }
        if m > 0 { return "idle \(m)m" }
        return "idle"
    }
}

extension JSONDecoder {
    public static let agentPing: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    public static let agentPing: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
