import Foundation

public final class ReportHandler {
    private let store: SessionStore

    public init(store: SessionStore? = nil) {
        self.store = store ?? SessionStore()
    }

    public func handle(sessionId: String, event: String, name: String?, file: String?, cwd: String? = nil, transcriptPath: String? = nil, app: String? = nil, contextPercent: Double? = nil) throws {
        var session = try store.read(id: sessionId) ?? Session(id: sessionId)

        // Update name: explicit name > derive from cwd > keep existing
        if let name, session.name == nil {
            session.name = name
        } else if session.name == nil, let cwd {
            session.name = URL(fileURLWithPath: cwd).lastPathComponent
        }

        if let file { session.file = file }
        if let cwd { session.cwd = cwd }
        if let app { session.app = app }

        // Store transcript path and extract task description
        if let transcriptPath {
            session.transcriptPath = transcriptPath
            // Always update to show the latest message
            session.taskDescription = Self.extractLastMessage(from: transcriptPath) ?? session.taskDescription
            // Prefer context % from hook stdin (authoritative), fall back to transcript parsing
            if let contextPercent {
                session.contextPercent = contextPercent
            } else {
                session.contextPercent = Self.readContextPercent(transcriptPath: transcriptPath)
            }
            // Extract provider and model from transcript
            if session.provider == nil || session.model == nil,
               let modelId = Self.readModelFromTranscript(transcriptPath),
               !modelId.hasPrefix("<") {
                let (provider, model) = Self.humanizeModelName(modelId)
                session.provider = provider
                session.model = model
            }
            // Calculate cost from token usage
            session.costUsd = Self.readCostFromTranscript(transcriptPath) ?? session.costUsd
        }

        // "stopped" = Claude finished its turn, waiting for user's next message = idle
        // Only sync/process-exit marks a session as truly "done"
        session.status = SessionStatus.from(event: event, current: session.status)

        session.lastEventAt = Date()
        try store.write(session)
    }

    /// Read the end of the transcript JSONL and find the last meaningful message.
    /// Prefers the last assistant text, falls back to the last user message.
    public static func extractLastMessage(from path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }

        // Read the last 100KB to find recent messages
        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 100_000)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        var lastAssistant: String?
        var lastUser: String?

        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            // Stop early once we have both
            if lastAssistant != nil && lastUser != nil { break }

            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = obj["type"] as? String
            let role = obj["role"] as? String

            let isAssistant = type == "assistant" || role == "assistant"
            let isUser = type == "user" || role == "human" || role == "user"

            guard isAssistant || isUser else { continue }

            let contentVal = obj["content"] ?? (obj["message"] as? [String: Any])?["content"]
            let text = extractText(from: contentVal)
            guard let text, !text.isEmpty else { continue }

            if isAssistant && lastAssistant == nil {
                lastAssistant = text
            } else if isUser && lastUser == nil {
                lastUser = text
            }
        }

        let result = lastAssistant ?? lastUser
        return result.map { truncate($0, maxLength: 300) }
    }

    /// Extract plain text from a transcript content value (string or array of blocks).
    private static func extractText(from contentVal: Any?) -> String? {
        if let text = contentVal as? String {
            let cleaned = stripTags(text)
            return cleaned.isEmpty ? nil : cleaned
        }
        if let blocks = contentVal as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text",
                      let text = block["text"] as? String else { return nil }
                let cleaned = stripTags(text)
                return cleaned.isEmpty ? nil : cleaned
            }
            return texts.first
        }
        return nil
    }

    /// Strip XML/HTML-like tags and command markup from text.
    private static func stripTags(_ text: String) -> String {
        // Remove <command-message>, <command-name>, <command-args> etc.
        var result = text
        // Extract command-args content if present (that's the actual user task)
        if let argsRange = result.range(of: "<command-args>"),
           let argsEnd = result.range(of: "</command-args>") {
            result = String(result[argsRange.upperBound..<argsEnd.lowerBound])
        }
        // Strip remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read real context usage from the last assistant message's token counts.
    /// Determines context window size from the model ID in the transcript.
    public static func readContextPercent(transcriptPath: String) -> Double? {
        // Read last 100KB of transcript to find the most recent assistant message with usage
        guard let fh = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { fh.closeFile() }

        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 100_000)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        // Search lines in reverse for the last assistant message with usage
        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any] ?? obj as [String: Any]?,
                  let usage = (msg["usage"] ?? obj["usage"]) as? [String: Any] else { continue }

            let inputTokens = (usage["input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let totalInput = inputTokens + cacheRead + cacheCreate

            if totalInput > 0 {
                let model = (obj["model"] as? String) ?? (msg["model"] as? String) ?? ""
                let contextWindow = Self.contextWindowSize(for: model)
                return min(Double(totalInput) / contextWindow, 1.0)
            }
        }
        return nil
    }

    /// Determine context window size from model ID.
    /// Checks for explicit suffix like [1m], then falls back to known model defaults.
    /// Opus models default to 1M context (their standard config in Claude Code).
    /// Other models default to 200K.
    static func contextWindowSize(for modelId: String) -> Double {
        let id = modelId.lowercased()

        // Explicit suffix from Claude Code: [1m], [500k], [200k], etc.
        if let regex = try? NSRegularExpression(pattern: #"\[(\d+)([km])\]"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)),
           let numRange = Range(match.range(at: 1), in: modelId),
           let unitRange = Range(match.range(at: 2), in: modelId),
           let num = Double(modelId[numRange]) {
            let unit = modelId[unitRange].lowercased()
            return unit == "m" ? num * 1_000_000.0 : num * 1_000.0
        }

        // Opus models have 1M context window by default
        if id.contains("opus") { return 1_000_000.0 }

        return 200_000.0
    }

    /// Parse a Claude model ID into (provider, displayName).
    /// e.g. "claude-opus-4-6" -> ("Claude", "Opus 4.6")
    /// e.g. "claude-haiku-4-5-20251001" -> ("Claude", "Haiku 4.5")
    public static func humanizeModelName(_ modelId: String) -> (provider: String, model: String) {
        guard modelId.hasPrefix("claude-") else {
            return ("Unknown", modelId)
        }
        // Strip "claude-" prefix
        let rest = String(modelId.dropFirst(7)) // drop "claude-"
        // Known families: opus, sonnet, haiku
        for family in ["opus", "sonnet", "haiku"] {
            guard rest.hasPrefix(family) else { continue }
            let afterFamily = String(rest.dropFirst(family.count))
            // afterFamily is like "-4-6" or "-4-5-20251001"
            let parts = afterFamily.split(separator: "-").compactMap { Int($0) }
            // Take first two numeric parts as major.minor version
            if parts.count >= 2 {
                return ("Claude", "\(family.capitalized) \(parts[0]).\(parts[1])")
            } else if parts.count == 1 {
                return ("Claude", "\(family.capitalized) \(parts[0])")
            }
            return ("Claude", family.capitalized)
        }
        return ("Claude", rest)
    }

    /// Extract the model ID from the last assistant message in a Claude transcript.
    public static func readModelFromTranscript(_ path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }

        let fileSize = fh.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 100_000)
        fh.seek(toFileOffset: fileSize - readSize)
        let data = fh.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines).reversed()
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant" else { continue }
            // Model can be at top level or nested in message
            if let model = obj["model"] as? String { return model }
            if let msg = obj["message"] as? [String: Any],
               let model = msg["model"] as? String { return model }
        }
        return nil
    }

    /// Calculate cumulative cost from all assistant messages in a Claude transcript.
    /// Streams the file in chunks with a rolling buffer to handle line boundaries,
    /// so it works correctly on large transcripts without loading the entire file.
    public static func readCostFromTranscript(_ path: String) -> Double? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fh.closeFile() }

        let chunkSize = 256 * 1024 // 256KB per read
        var totalCost = 0.0
        var leftover = ""

        while true {
            let data = fh.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            guard let chunk = String(data: data, encoding: .utf8) else { continue }

            let combined = leftover + chunk
            var lines = combined.components(separatedBy: "\n")
            // Last element may be an incomplete line -- save for next iteration
            leftover = lines.removeLast()

            for line in lines {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "assistant" else { continue }

                let msg = obj["message"] as? [String: Any]
                guard let usage = (msg?["usage"] ?? obj["usage"]) as? [String: Any] else { continue }

                let model = (msg?["model"] ?? obj["model"]) as? String ?? ""
                let pricing = tokenPricing(for: model)

                let inputTokens = (usage["input_tokens"] as? Int) ?? 0
                let outputTokens = (usage["output_tokens"] as? Int) ?? 0
                let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
                let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0

                totalCost += Double(inputTokens) * pricing.input / 1_000_000.0
                totalCost += Double(outputTokens) * pricing.output / 1_000_000.0
                totalCost += Double(cacheRead) * pricing.cacheRead / 1_000_000.0
                totalCost += Double(cacheCreate) * pricing.cacheWrite / 1_000_000.0
            }
        }

        // Process any remaining partial line
        if !leftover.isEmpty,
           let lineData = leftover.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
           obj["type"] as? String == "assistant" {
            let msg = obj["message"] as? [String: Any]
            if let usage = (msg?["usage"] ?? obj["usage"]) as? [String: Any] {
                let model = (msg?["model"] ?? obj["model"]) as? String ?? ""
                let pricing = tokenPricing(for: model)
                let inputTokens = (usage["input_tokens"] as? Int) ?? 0
                let outputTokens = (usage["output_tokens"] as? Int) ?? 0
                let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
                let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                totalCost += Double(inputTokens) * pricing.input / 1_000_000.0
                totalCost += Double(outputTokens) * pricing.output / 1_000_000.0
                totalCost += Double(cacheRead) * pricing.cacheRead / 1_000_000.0
                totalCost += Double(cacheCreate) * pricing.cacheWrite / 1_000_000.0
            }
        }

        return totalCost > 0 ? totalCost : nil
    }

    /// Per-million-token pricing for Claude models.
    private static func tokenPricing(for model: String) -> (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        if model.contains("opus") {
            return (input: 15.0, output: 75.0, cacheRead: 1.50, cacheWrite: 18.75)
        } else if model.contains("haiku") {
            return (input: 0.80, output: 4.0, cacheRead: 0.08, cacheWrite: 1.0)
        } else {
            // Default to Sonnet pricing
            return (input: 3.0, output: 15.0, cacheRead: 0.30, cacheWrite: 3.75)
        }
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse multiple newlines into single space for compact display
        let collapsed = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "..."
    }
}
