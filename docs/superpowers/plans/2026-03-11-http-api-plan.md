# HTTP API + Hover Preview Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed an HTTP API server in AgentPing so any AI tool can report/query sessions, add provider/model tracking, and show a hover preview on session rows.

**Architecture:** Lightweight HTTP server using NWListener (Network.framework) embedded in the menu bar app. CLI becomes an HTTP client with file-based fallback. Two new session fields (provider, model) with auto-extraction from Claude transcripts.

**Tech Stack:** Swift, NWListener (Network.framework), URLSession (client), SwiftUI popover

**Spec:** `docs/superpowers/specs/2026-03-11-http-api-design.md`

---

## Chunk 1: Session Model + Model Extraction

### Task 1: Add provider and model fields to Session

**Files:**
- Modify: `Sources/AgentPingCore/Models/Session.swift`
- Modify: `Tests/AgentPingCoreTests/SessionTests.swift`

- [ ] **Step 1: Write failing test for new fields**

Add to `Tests/AgentPingCoreTests/SessionTests.swift`:

```swift
func testSessionWithProviderAndModel() throws {
    let json = """
    {
        "id": "test-model",
        "status": "running",
        "provider": "Claude",
        "model": "Opus 4.6",
        "startedAt": "2026-03-10T10:00:00Z",
        "lastEventAt": "2026-03-10T10:14:22Z",
        "notifications": true
    }
    """.data(using: .utf8)!

    let session = try JSONDecoder.agentPing.decode(Session.self, from: json)
    XCTAssertEqual(session.provider, "Claude")
    XCTAssertEqual(session.model, "Opus 4.6")
}

func testSessionWithoutProviderAndModel() throws {
    let json = """
    {
        "id": "test-no-model",
        "status": "running",
        "startedAt": "2026-03-10T10:00:00Z",
        "lastEventAt": "2026-03-10T10:14:22Z",
        "notifications": true
    }
    """.data(using: .utf8)!

    let session = try JSONDecoder.agentPing.decode(Session.self, from: json)
    XCTAssertNil(session.provider)
    XCTAssertNil(session.model)
}

func testSessionRoundTripWithModel() throws {
    let session = Session(
        id: "rt-1",
        status: .running,
        provider: "Copilot",
        model: "GPT-5.3-Codex"
    )
    let data = try JSONEncoder.agentPing.encode(session)
    let decoded = try JSONDecoder.agentPing.decode(Session.self, from: data)
    XCTAssertEqual(decoded.provider, "Copilot")
    XCTAssertEqual(decoded.model, "GPT-5.3-Codex")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTests`
Expected: FAIL - `Session` has no `provider`/`model` properties

- [ ] **Step 3: Add provider and model to Session**

In `Sources/AgentPingCore/Models/Session.swift`:

Add two fields to the struct after `pinned`:
```swift
public var provider: String?
public var model: String?
```

Add to `init` parameters (after `pinned: Bool = false`):
```swift
provider: String? = nil,
model: String? = nil
```

Add to `init` body:
```swift
self.provider = provider
self.model = model
```

Add to `CodingKeys` enum:
```swift
case provider, model
```

Add to `init(from decoder:)` after the pinned line:
```swift
provider = try container.decodeIfPresent(String.self, forKey: .provider)
model = try container.decodeIfPresent(String.self, forKey: .model)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionTests`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/Models/Session.swift Tests/AgentPingCoreTests/SessionTests.swift
git commit -m "feat: add provider and model fields to Session"
```

### Task 2: Extract model from Claude transcripts

**Files:**
- Modify: `Sources/AgentPingCore/CLI/ReportHandler.swift`
- Create: `Tests/AgentPingCoreTests/ModelExtractionTests.swift`

- [ ] **Step 1: Write failing tests for model extraction**

Create `Tests/AgentPingCoreTests/ModelExtractionTests.swift`:

```swift
import XCTest
@testable import AgentPingCore

final class ModelExtractionTests: XCTestCase {
    var tempDir: URL!
    var store: SessionStore!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-model-test-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testExtractsClaudeOpusModel() throws {
        let transcript = tempDir.appendingPathComponent("transcript.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","model":"claude-opus-4-6","message":{"content":"hello","usage":{"input_tokens":100}}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "model-test", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: transcript.path)

        let session = try store.read(id: "model-test")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Opus 4.6")
    }

    func testExtractsClaudeSonnetModel() throws {
        let transcript = tempDir.appendingPathComponent("transcript2.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","model":"claude-sonnet-4-6","message":{"content":"hello","usage":{"input_tokens":100}}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "sonnet-test", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: transcript.path)

        let session = try store.read(id: "sonnet-test")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Sonnet 4.6")
    }

    func testExtractsClaudeHaikuModel() throws {
        let transcript = tempDir.appendingPathComponent("transcript3.jsonl")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","model":"claude-haiku-4-5-20251001","message":{"content":"hello","usage":{"input_tokens":100}}}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "haiku-test", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: transcript.path)

        let session = try store.read(id: "haiku-test")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Haiku 4.5")
    }

    func testNoModelWithoutTranscript() throws {
        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "no-transcript", event: "tool-use", name: nil, file: nil, cwd: "/tmp", transcriptPath: nil)

        let session = try store.read(id: "no-transcript")
        XCTAssertNil(session?.provider)
        XCTAssertNil(session?.model)
    }

    func testHumanizeModelName() {
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-opus-4-6"), ("Claude", "Opus 4.6"))
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-sonnet-4-6"), ("Claude", "Sonnet 4.6"))
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-haiku-4-5-20251001"), ("Claude", "Haiku 4.5"))
        XCTAssertEqual(ReportHandler.humanizeModelName("claude-sonnet-4-5-20241022"), ("Claude", "Sonnet 4.5"))
        XCTAssertEqual(ReportHandler.humanizeModelName("unknown-model"), ("Unknown", "unknown-model"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModelExtractionTests`
Expected: FAIL - no `humanizeModelName` method, no provider/model assignment

- [ ] **Step 3: Implement model extraction in ReportHandler**

In `Sources/AgentPingCore/CLI/ReportHandler.swift`, add the public static method:

```swift
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
```

Add a private static method to read the model from transcript:

```swift
/// Extract the model ID from the last assistant message in a Claude transcript.
private static func readModelFromTranscript(_ path: String) -> String? {
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
              obj["type"] as? String == "assistant",
              let model = obj["model"] as? String else { continue }
        return model
    }
    return nil
}
```

Update the `handle()` method -- in the `if let transcriptPath` block, after the contextPercent line, add:

```swift
// Extract provider and model from transcript
if session.provider == nil || session.model == nil,
   let modelId = Self.readModelFromTranscript(transcriptPath) {
    let (provider, model) = Self.humanizeModelName(modelId)
    session.provider = provider
    session.model = model
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelExtractionTests`
Expected: All PASS

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentPingCore/CLI/ReportHandler.swift Tests/AgentPingCoreTests/ModelExtractionTests.swift
git commit -m "feat: extract provider and model from Claude transcripts"
```

---

## Chunk 2: HTTP Server

### Task 3: HTTP request/response types and parser

**Files:**
- Create: `Sources/AgentPingCore/API/HTTPParser.swift`
- Create: `Tests/AgentPingCoreTests/HTTPParserTests.swift`

- [ ] **Step 1: Write failing tests for HTTP parsing**

Create `Tests/AgentPingCoreTests/HTTPParserTests.swift`:

```swift
import XCTest
@testable import AgentPingCore

final class HTTPParserTests: XCTestCase {
    func testParseGetRequest() throws {
        let raw = "GET /v1/sessions HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try HTTPRequestParser.parse(Data(raw.utf8))
        XCTAssertEqual(request.method, .GET)
        XCTAssertEqual(request.path, "/v1/sessions")
        XCTAssertNil(request.body)
    }

    func testParsePostWithBody() throws {
        let body = #"{"session_id":"abc","event":"tool-use"}"#
        let raw = "POST /v1/report HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: application/json\r\n\r\n\(body)"
        let request = try HTTPRequestParser.parse(Data(raw.utf8))
        XCTAssertEqual(request.method, .POST)
        XCTAssertEqual(request.path, "/v1/report")
        XCTAssertEqual(request.body, Data(body.utf8))
    }

    func testParseDeleteRequest() throws {
        let raw = "DELETE /v1/sessions/abc-123 HTTP/1.1\r\n\r\n"
        let request = try HTTPRequestParser.parse(Data(raw.utf8))
        XCTAssertEqual(request.method, .DELETE)
        XCTAssertEqual(request.path, "/v1/sessions/abc-123")
    }

    func testParseMalformedRequest() {
        let raw = "GARBAGE\r\n\r\n"
        XCTAssertThrowsError(try HTTPRequestParser.parse(Data(raw.utf8)))
    }

    func testParseIncompleteHeaders() {
        let raw = "GET /v1/sessions HTTP/1.1\r\nHost: local"
        // No \r\n\r\n terminator -- should return nil (incomplete)
        XCTAssertNil(HTTPRequestParser.parseIfComplete(Data(raw.utf8)))
    }

    func testParseIncompleteBody() {
        let raw = "POST /v1/report HTTP/1.1\r\nContent-Length: 100\r\n\r\nshort"
        // Body shorter than Content-Length -- should return nil (incomplete)
        XCTAssertNil(HTTPRequestParser.parseIfComplete(Data(raw.utf8)))
    }

    func testFormatResponse200() {
        let body = #"{"status":"ok"}"#
        let response = HTTPResponse(status: 200, statusText: "OK", body: Data(body.utf8))
        let data = response.serialize()
        let str = String(data: data, encoding: .utf8)!
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(str.contains("Content-Length: \(body.utf8.count)"))
        XCTAssertTrue(str.hasSuffix(body))
    }

    func testFormatResponse404() {
        let response = HTTPResponse(status: 404, statusText: "Not Found", body: nil)
        let str = String(data: response.serialize(), encoding: .utf8)!
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(str.contains("Content-Length: 0"))
    }

    func testRejectsOversizedHeaders() {
        // Header section > 8KB
        let longHeader = String(repeating: "X", count: 9000)
        let raw = "GET /v1/sessions HTTP/1.1\r\nX-Big: \(longHeader)\r\n\r\n"
        XCTAssertThrowsError(try HTTPRequestParser.parse(Data(raw.utf8)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HTTPParserTests`
Expected: FAIL - no `HTTPRequestParser` type

- [ ] **Step 3: Create directory and implement HTTPParser**

Run: `mkdir -p Sources/AgentPingCore/API`

Create `Sources/AgentPingCore/API/HTTPParser.swift`:

```swift
import Foundation

public enum HTTPMethod: String {
    case GET, POST, PUT, DELETE, OPTIONS
}

public struct HTTPRequest {
    public let method: HTTPMethod
    public let path: String
    public let headers: [String: String]
    public let body: Data?
}

public struct HTTPResponse {
    public let status: Int
    public let statusText: String
    public let body: Data?
    public var headers: [String: String] = [:]

    public func serialize() -> Data {
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body?.count ?? 0)"
        allHeaders["Content-Type"] = allHeaders["Content-Type"] ?? "application/json"
        allHeaders["Connection"] = "close"

        var result = "HTTP/1.1 \(status) \(statusText)\r\n"
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            result += "\(key): \(value)\r\n"
        }
        result += "\r\n"

        var data = Data(result.utf8)
        if let body {
            data.append(body)
        }
        return data
    }

    public static func json(_ status: Int, _ statusText: String, _ obj: Any) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, statusText: statusText, body: body)
    }

    public static func error(_ status: Int, _ statusText: String, _ message: String) -> HTTPResponse {
        return json(status, statusText, ["error": message])
    }

    public static let notFound = error(404, "Not Found", "Not found")
    public static let methodNotAllowed = error(405, "Method Not Allowed", "Method not allowed")
}

public enum HTTPParseError: Error {
    case malformedRequestLine
    case unknownMethod(String)
    case headersTooLarge
}

public enum HTTPRequestParser {
    private static let maxHeaderSize = 8192  // 8KB
    private static let maxBodySize = 1_048_576  // 1MB
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Parse a complete HTTP request from raw data. Throws on malformed input.
    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard let request = try parseInternal(data) else {
            throw HTTPParseError.malformedRequestLine
        }
        return request
    }

    /// Parse if the data contains a complete HTTP request. Returns nil if incomplete.
    public static func parseIfComplete(_ data: Data) -> HTTPRequest? {
        return try? parseInternal(data, allowIncomplete: true)
    }

    private static func parseInternal(_ data: Data, allowIncomplete: Bool = false) throws -> HTTPRequest? {
        // Find header/body boundary
        guard let separatorRange = data.range(of: headerTerminator) else {
            if allowIncomplete { return nil }
            throw HTTPParseError.malformedRequestLine
        }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]
        if headerData.count > maxHeaderSize {
            throw HTTPParseError.headersTooLarge
        }

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw HTTPParseError.malformedRequestLine
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPParseError.malformedRequestLine
        }

        // Parse request line: "METHOD /path HTTP/1.1"
        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            throw HTTPParseError.malformedRequestLine
        }

        guard let method = HTTPMethod(rawValue: String(parts[0])) else {
            throw HTTPParseError.unknownMethod(String(parts[0]))
        }

        let path = String(parts[1])

        // Parse headers
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key.lowercased()] = value
        }

        // Parse body
        let bodyStart = separatorRange.upperBound
        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        var body: Data?

        if contentLength > 0 {
            let available = data.count - bodyStart
            if available < contentLength {
                if allowIncomplete { return nil }
                throw HTTPParseError.malformedRequestLine
            }
            body = data[bodyStart..<bodyStart + contentLength]
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HTTPParserTests`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/API/HTTPParser.swift Tests/AgentPingCoreTests/HTTPParserTests.swift
git commit -m "feat: add minimal HTTP request/response parser"
```

### Task 4: API router

**Files:**
- Create: `Sources/AgentPingCore/API/APIRouter.swift`
- Create: `Tests/AgentPingCoreTests/APIRouterTests.swift`

- [ ] **Step 1: Write failing tests for routing**

Create `Tests/AgentPingCoreTests/APIRouterTests.swift`:

```swift
import XCTest
@testable import AgentPingCore

final class APIRouterTests: XCTestCase {
    var store: SessionStore!
    var tempDir: URL!
    var router: APIRouter!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-router-test-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
        router = APIRouter(store: store)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testHealthEndpoint() throws {
        let req = HTTPRequest(method: .GET, path: "/v1/health", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 200)
        let json = try JSONSerialization.jsonObject(with: res.body!) as! [String: Any]
        XCTAssertEqual(json["status"] as? String, "ok")
    }

    func testReportCreatesSession() throws {
        let body = #"{"session_id":"test-1","event":"tool-use","cwd":"/tmp/proj","provider":"Claude","model":"Opus 4.6"}"#
        let req = HTTPRequest(method: .POST, path: "/v1/report", headers: ["content-type": "application/json"], body: Data(body.utf8))
        let res = router.handle(req)
        XCTAssertEqual(res.status, 200)

        let session = try store.read(id: "test-1")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.status, .running)
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Opus 4.6")
    }

    func testReportMissingSessionId() throws {
        let body = #"{"event":"tool-use"}"#
        let req = HTTPRequest(method: .POST, path: "/v1/report", headers: [:], body: Data(body.utf8))
        let res = router.handle(req)
        XCTAssertEqual(res.status, 400)
    }

    func testReportMissingEvent() throws {
        let body = #"{"session_id":"test-2"}"#
        let req = HTTPRequest(method: .POST, path: "/v1/report", headers: [:], body: Data(body.utf8))
        let res = router.handle(req)
        XCTAssertEqual(res.status, 400)
    }

    func testListSessions() throws {
        let s1 = Session(id: "s1", status: .running, provider: "Claude", model: "Opus 4.6")
        let s2 = Session(id: "s2", status: .needsInput)
        try store.write(s1)
        try store.write(s2)

        let req = HTTPRequest(method: .GET, path: "/v1/sessions", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 200)
        let sessions = try JSONDecoder.agentPing.decode([Session].self, from: res.body!)
        XCTAssertEqual(sessions.count, 2)
    }

    func testListSessionsFilterByStatus() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .done)
        try store.write(s1)
        try store.write(s2)

        let req = HTTPRequest(method: .GET, path: "/v1/sessions?status=running", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 200)
        let sessions = try JSONDecoder.agentPing.decode([Session].self, from: res.body!)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "s1")
    }

    func testGetSession() throws {
        let s1 = Session(id: "abc-123", status: .running)
        try store.write(s1)

        let req = HTTPRequest(method: .GET, path: "/v1/sessions/abc-123", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 200)
        let session = try JSONDecoder.agentPing.decode(Session.self, from: res.body!)
        XCTAssertEqual(session.id, "abc-123")
    }

    func testGetSessionNotFound() {
        let req = HTTPRequest(method: .GET, path: "/v1/sessions/nonexistent", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 404)
    }

    func testDeleteSession() throws {
        let s1 = Session(id: "del-1", status: .done)
        try store.write(s1)

        let req = HTTPRequest(method: .DELETE, path: "/v1/sessions/del-1", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 204)

        let loaded = try store.read(id: "del-1")
        XCTAssertNil(loaded)
    }

    func testDeleteSessionNotFound() {
        let req = HTTPRequest(method: .DELETE, path: "/v1/sessions/nonexistent", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 404)
    }

    func testUnknownPath() {
        let req = HTTPRequest(method: .GET, path: "/v1/unknown", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 404)
    }

    func testWrongMethodOnReport() {
        let req = HTTPRequest(method: .GET, path: "/v1/report", headers: [:], body: nil)
        let res = router.handle(req)
        XCTAssertEqual(res.status, 405)
    }

    func testReportWithAllFields() throws {
        let body = """
        {"session_id":"full-1","event":"needs-input","name":"my-proj","cwd":"/tmp","file":"main.swift","app":"Ghostty","provider":"Claude","model":"Opus 4.6","pid":12345}
        """
        let req = HTTPRequest(method: .POST, path: "/v1/report", headers: [:], body: Data(body.utf8))
        let res = router.handle(req)
        XCTAssertEqual(res.status, 200)

        let session = try store.read(id: "full-1")
        XCTAssertEqual(session?.status, .needsInput)
        XCTAssertEqual(session?.app, "Ghostty")
        XCTAssertEqual(session?.cwd, "/tmp")
        XCTAssertEqual(session?.provider, "Claude")
        XCTAssertEqual(session?.model, "Opus 4.6")
        XCTAssertEqual(session?.pid, 12345)
    }

    func testReportUpdatesExistingSession() throws {
        // First report creates session
        let body1 = #"{"session_id":"upd-1","event":"tool-use","cwd":"/tmp","provider":"Claude","model":"Opus 4.6"}"#
        let req1 = HTTPRequest(method: .POST, path: "/v1/report", headers: [:], body: Data(body1.utf8))
        _ = router.handle(req1)

        // Second report updates status
        let body2 = #"{"session_id":"upd-1","event":"needs-input"}"#
        let req2 = HTTPRequest(method: .POST, path: "/v1/report", headers: [:], body: Data(body2.utf8))
        let res = router.handle(req2)
        XCTAssertEqual(res.status, 200)

        let session = try store.read(id: "upd-1")
        XCTAssertEqual(session?.status, .needsInput)
        // Should preserve cwd from first report
        XCTAssertEqual(session?.cwd, "/tmp")
        XCTAssertEqual(session?.provider, "Claude")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter APIRouterTests`
Expected: FAIL - no `APIRouter` type

- [ ] **Step 3: Implement APIRouter**

Create `Sources/AgentPingCore/API/APIRouter.swift`:

```swift
import Foundation

public final class APIRouter {
    private let store: SessionStore
    private let version: String

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
        return .json(200, "OK", ["status": "ok", "version": version])
    }

    private func handleReport(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return .error(400, "Bad Request", "Invalid JSON body")
        }

        guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else {
            return .error(400, "Bad Request", "session_id is required")
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
            if let transcriptPath = json["transcript_path"] as? String { session.transcriptPath = transcriptPath }
            if let provider = json["provider"] as? String { session.provider = provider }
            if let model = json["model"] as? String { session.model = model }
            if let pid = json["pid"] as? Int { session.pid = pid }

            // Map event to status
            switch event {
            case "tool-use":    session.status = .running
            case "needs-input": session.status = .needsInput
            case "stopped":     session.status = .idle
            case "error":       session.status = .error
            default:            session.status = .running
            }

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter APIRouterTests`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/API/APIRouter.swift Tests/AgentPingCoreTests/APIRouterTests.swift
git commit -m "feat: add API router with report, sessions, health endpoints"
```

### Task 5: NWListener-based HTTP server

**Files:**
- Create: `Sources/AgentPingCore/API/APIServer.swift`
- Create: `Tests/AgentPingCoreTests/APIServerTests.swift`

- [ ] **Step 1: Write failing integration tests**

Create `Tests/AgentPingCoreTests/APIServerTests.swift`:

```swift
import XCTest
@testable import AgentPingCore

final class APIServerTests: XCTestCase {
    var server: APIServer!
    var tempDir: URL!
    var store: SessionStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-server-test-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
        // Use random port to avoid conflicts in parallel test runs
        server = APIServer(store: store, port: 0)
        try await server.start()
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(server.actualPort)")!
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, response as! HTTPURLResponse)
    }

    func testHealthEndpoint() async throws {
        let (data, response) = try await request("GET", "v1/health")
        XCTAssertEqual(response.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["status"] as? String, "ok")
    }

    func testReportAndGetSession() async throws {
        let body = #"{"session_id":"integ-1","event":"tool-use","cwd":"/tmp","provider":"Claude","model":"Opus 4.6"}"#
        let (_, postRes) = try await request("POST", "v1/report", body: Data(body.utf8))
        XCTAssertEqual(postRes.statusCode, 200)

        let (getData, getRes) = try await request("GET", "v1/sessions/integ-1")
        XCTAssertEqual(getRes.statusCode, 200)
        let session = try JSONDecoder.agentPing.decode(Session.self, from: getData)
        XCTAssertEqual(session.provider, "Claude")
        XCTAssertEqual(session.model, "Opus 4.6")
    }

    func testListAndDeleteSession() async throws {
        let body = #"{"session_id":"list-1","event":"tool-use"}"#
        _ = try await request("POST", "v1/report", body: Data(body.utf8))

        let (listData, listRes) = try await request("GET", "v1/sessions")
        XCTAssertEqual(listRes.statusCode, 200)
        let sessions = try JSONDecoder.agentPing.decode([Session].self, from: listData)
        XCTAssertEqual(sessions.count, 1)

        let (_, delRes) = try await request("DELETE", "v1/sessions/list-1")
        XCTAssertEqual(delRes.statusCode, 204)

        let (listData2, _) = try await request("GET", "v1/sessions")
        let sessions2 = try JSONDecoder.agentPing.decode([Session].self, from: listData2)
        XCTAssertEqual(sessions2.count, 0)
    }

    func testConcurrentReports() async throws {
        // Send 10 concurrent reports
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let body = #"{"session_id":"concurrent-\#(i)","event":"tool-use"}"#
                    let (_, res) = try await self.request("POST", "v1/report", body: Data(body.utf8))
                    XCTAssertEqual(res.statusCode, 200)
                }
            }
            try await group.waitForAll()
        }

        let sessions = try store.listAll()
        XCTAssertEqual(sessions.count, 10)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter APIServerTests`
Expected: FAIL - no `APIServer` type

- [ ] **Step 3: Implement APIServer**

Create `Sources/AgentPingCore/API/APIServer.swift`:

```swift
import Foundation
import Network

public final class APIServer {
    private var listener: NWListener?
    private let router: APIRouter
    private let queue = DispatchQueue(label: "com.agentping.api", qos: .utility)
    private let requestedPort: UInt16
    private(set) public var actualPort: UInt16 = 0

    /// Port file location: ~/.agentping/port
    private static var portFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentping/port")
    }

    public init(store: SessionStore, port: UInt16 = 19199) {
        self.requestedPort = port
        self.router = APIRouter(store: store)
    }

    public func start() async throws {
        let port: NWEndpoint.Port
        if requestedPort == 0 {
            // Random port for testing
            port = .any
        } else {
            port = NWEndpoint.Port(rawValue: requestedPort) ?? .any
        }

        let params = NWParameters.tcp
        params.acceptLocalOnly = true

        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        self?.actualPort = port.rawValue
                        self?.writePortFile()
                    }
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        removePortFile()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        var buffer = Data()
        receiveData(connection: connection, buffer: &buffer)
    }

    private func receiveData(connection: NWConnection, buffer: inout Data) {
        var buffer = buffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let data {
                buffer.append(data)
            }

            // Check for oversized request
            if buffer.count > 1_048_576 + 8192 {
                let response = HTTPResponse.error(413, "Payload Too Large", "Request too large")
                self.send(response, on: connection)
                return
            }

            // Try to parse the complete request
            if let request = HTTPRequestParser.parseIfComplete(buffer) {
                let response = self.router.handle(request)
                self.send(response, on: connection)
                return
            }

            // If connection is complete but we couldn't parse, it's malformed
            if isComplete || error != nil {
                let response = HTTPResponse.error(400, "Bad Request", "Malformed HTTP request")
                self.send(response, on: connection)
                return
            }

            // Otherwise, keep reading
            self.receiveData(connection: connection, buffer: &buffer)
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.serialize()
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func writePortFile() {
        let url = Self.portFilePath
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(actualPort)".write(to: url, atomically: true, encoding: .utf8)
    }

    private func removePortFile() {
        try? FileManager.default.removeItem(at: Self.portFilePath)
    }

    /// Read the port from the port file. Returns nil if not available.
    public static func readPort() -> UInt16? {
        guard let content = try? String(contentsOf: portFilePath, encoding: .utf8),
              let port = UInt16(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return port
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter APIServerTests`
Expected: All PASS

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentPingCore/API/APIServer.swift Tests/AgentPingCoreTests/APIServerTests.swift
git commit -m "feat: add NWListener-based HTTP API server"
```

---

## Chunk 3: CLI HTTP Client + App Integration

### Task 6: Update CLI to use HTTP-first with file fallback

**Files:**
- Modify: `Sources/AgentPingCLI/main.swift`

- [ ] **Step 1: Add an APIClient helper to main.swift**

Add before `AgentPingCommand`:

```swift
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
```

- [ ] **Step 2: Update Report command to try HTTP first**

Replace the `func run()` in `Report` struct:

```swift
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
    if let app = Self.detectApp() { payload["app"] = app }

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
        app: Self.detectApp()
    )
}
```

- [ ] **Step 3: Update List command to try HTTP first**

Replace `func run()` in `List` struct:

```swift
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
```

- [ ] **Step 4: Update Status command to try HTTP first**

Replace `func run()` in `Status` struct:

```swift
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
```

- [ ] **Step 5: Update Delete command to try HTTP first**

Replace `func run()` in `Delete` struct:

```swift
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
```

- [ ] **Step 6: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentPingCLI/main.swift
git commit -m "feat: CLI uses HTTP API with file-based fallback"
```

### Task 7: Start API server in the menu bar app

**Files:**
- Modify: `Sources/AgentPing/AgentPingApp.swift`

- [ ] **Step 1: Add server to AppDelegate**

In `Sources/AgentPing/AgentPingApp.swift`, add property to `AppDelegate`:

```swift
var apiServer: APIServer?
```

In `applicationDidFinishLaunching`, after `manager.autoPurgeOldSessions()` (line 63), add:

```swift
// Start API server
let port = UInt16(UserDefaults.standard.integer(forKey: "apiPort"))
apiServer = APIServer(store: manager.store, port: port > 0 ? port : 19199)
Task {
    do {
        try await apiServer?.start()
    } catch {
        // Server failed to start -- app continues with file-based IPC
        print("API server failed to start: \(error)")
    }
}
```

Note: `SessionManager` currently initializes its own `SessionStore` privately. We need to expose it. Add this to `SessionManager`:

In `Sources/AgentPingCore/Manager/SessionManager.swift`, change `private let store` to:

```swift
public let store: SessionStore
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentPing/AgentPingApp.swift Sources/AgentPingCore/Manager/SessionManager.swift
git commit -m "feat: start API server on app launch"
```

### Task 8: Add API port to Preferences

**Files:**
- Modify: `Sources/AgentPing/Views/PreferencesView.swift`

- [ ] **Step 1: Add port setting to PreferencesView**

Add a new `@AppStorage` property:

```swift
@AppStorage("apiPort") private var apiPort = 19199
```

Add a new section after "Data" and before "Hooks":

```swift
Section("API") {
    HStack {
        Text("Port")
        TextField("Port", value: $apiPort, format: .number)
            .frame(width: 80)
            .textFieldStyle(.roundedBorder)
            .onChange(of: apiPort) { _, newValue in
                // Clamp to valid port range
                if newValue < 1024 { apiPort = 1024 }
                if newValue > 65535 { apiPort = 65535 }
            }
    }
    Text("API server runs on localhost:\(apiPort). Restart app after changing port.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

Update the frame height to accommodate the new section:

Change `.frame(width: 400, height: 360)` to `.frame(width: 400, height: 440)`

Also update the preferences window size in `AgentPingApp.swift` -- change `NSRect(x: 0, y: 0, width: 400, height: 360)` to `NSRect(x: 0, y: 0, width: 400, height: 440)`.

- [ ] **Step 2: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentPing/Views/PreferencesView.swift Sources/AgentPing/AgentPingApp.swift
git commit -m "feat: add API port setting to Preferences"
```

---

## Chunk 4: Hover Preview

### Task 9: Session hover preview

**Files:**
- Create: `Sources/AgentPing/Views/SessionHoverView.swift`
- Modify: `Sources/AgentPing/Views/SessionRowView.swift`

- [ ] **Step 1: Create SessionHoverView**

Create `Sources/AgentPing/Views/SessionHoverView.swift`:

```swift
import SwiftUI
import AgentPingCore

struct SessionHoverView: View {
    let session: Session
    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider + Model
            HStack(spacing: 6) {
                Text(modelLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(session.status.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            // Task description
            if let task = session.taskDescription, !task.isEmpty {
                Text(task)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Context bar
            if let pct = session.contextPercent, pct > 0 {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(contextBarColor(pct))
                                .frame(width: geo.size.width * min(pct, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            // Cost
            if costTrackingEnabled, let cost = session.costUsd, cost > 0 {
                HStack {
                    Text("Cost")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "$%.2f", cost))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // cwd
            if let cwd = session.cwd, !cwd.isEmpty {
                HStack {
                    Text("Path")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(displayPath(cwd))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private var modelLabel: String {
        let parts = [session.provider, session.model].compactMap { $0 }
        return parts.isEmpty ? "Unknown model" : parts.joined(separator: " ")
    }

    private var statusColor: Color {
        switch session.status {
        case .running:    return Color(.systemGreen)
        case .needsInput: return Color(.systemOrange)
        case .idle:       return Color(.systemBlue)
        case .error:      return Color(.systemRed)
        case .done:       return Color(.systemGray)
        case .unavailable: return Color(.systemGray)
        }
    }

    private func contextBarColor(_ pct: Double) -> Color {
        if pct > 0.85 { return Color(.systemRed).opacity(0.8) }
        if pct > 0.65 { return Color(.systemOrange).opacity(0.7) }
        return Color(.systemGreen).opacity(0.5)
    }

    private func displayPath(_ cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }
}
```

- [ ] **Step 2: Add hover popover trigger to SessionRowView**

In `Sources/AgentPing/Views/SessionRowView.swift`, add a state variable after `isHovered`:

```swift
@State private var showHover = false
@State private var hoverTask: DispatchWorkItem?
```

Replace the `.onHover { isHovered = $0 }` line with:

```swift
.onHover { hovering in
    isHovered = hovering
    hoverTask?.cancel()
    if hovering {
        let task = DispatchWorkItem { showHover = true }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    } else {
        showHover = false
    }
}
.popover(isPresented: $showHover, arrowEdge: .trailing) {
    SessionHoverView(session: session)
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPing/Views/SessionHoverView.swift Sources/AgentPing/Views/SessionRowView.swift
git commit -m "feat: add session hover preview with provider/model display"
```

---

## Chunk 5: Final Integration + Testing

### Task 10: Run full test suite

- [ ] **Step 1: Run all unit tests**

Run: `swift test`
Expected: All PASS

- [ ] **Step 2: Build release binary**

Run: `swift build -c release`
Expected: Build succeeds

- [ ] **Step 3: Manual smoke test -- API server**

Run the app and test with curl:

```bash
# Start the app
./Scripts/package_app.sh && open AgentPing.app

# Health check
curl -s http://localhost:19199/v1/health | python3 -m json.tool

# Report a session
curl -s -X POST http://localhost:19199/v1/report \
  -d '{"session_id":"curl-test","event":"tool-use","cwd":"/tmp","provider":"Copilot","model":"GPT-5.3-Codex"}' | python3 -m json.tool

# List sessions
curl -s http://localhost:19199/v1/sessions | python3 -m json.tool

# Get single session
curl -s http://localhost:19199/v1/sessions/curl-test | python3 -m json.tool

# Delete session
curl -s -X DELETE http://localhost:19199/v1/sessions/curl-test
```

- [ ] **Step 4: Manual smoke test -- CLI with HTTP**

```bash
# Report via CLI (should use HTTP)
.build/release/agentping report --session test-cli --event tool-use

# List via CLI
.build/release/agentping list
.build/release/agentping list --json

# Status
.build/release/agentping status

# Delete
.build/release/agentping delete test-cli
```

- [ ] **Step 5: Manual smoke test -- CLI fallback (app not running)**

```bash
# Stop the app
pkill AgentPingApp

# Report should fall back to file write
.build/release/agentping report --session fallback-test --event tool-use

# Verify file was written
cat ~/.agentping/sessions/fallback-test.json
```

- [ ] **Step 6: Manual smoke test -- hover preview**

Open the app, hover over a session row for ~0.5s, verify the popover appears with model/provider info.

- [ ] **Step 7: Verify existing hooks still work**

Existing Claude Code hooks call `agentping report` -- verify they still work by starting a Claude Code session and checking AgentPing picks it up.

- [ ] **Step 8: Clean up test sessions**

```bash
.build/release/agentping clear --all
rm -f ~/.agentping/sessions/curl-test.json ~/.agentping/sessions/fallback-test.json
```
