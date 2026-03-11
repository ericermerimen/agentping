import Foundation

public enum SessionStatus: String, Codable, CaseIterable {
    case running
    case needsInput = "needs-input"
    case idle
    case done
    case error
    case unavailable
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
        model: String? = nil
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
    }
}

// Custom decoding to handle backward compatibility (pinned may not exist in old JSON)
extension Session {
    enum CodingKeys: String, CodingKey {
        case id, name, status, app, pid, windowId, cwd, file
        case startedAt, lastEventAt, notifications, costUsd
        case transcriptPath, taskDescription, contextPercent, pinned
        case provider, model
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
