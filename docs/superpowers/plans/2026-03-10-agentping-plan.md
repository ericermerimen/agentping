# AgentPing Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 14+ menu bar app that monitors Claude Code sessions, shows their status, and lets users jump to the correct window.

**Architecture:** Three layers -- data (process scanner + hook CLI + session JSON files), state (SessionManager with FSEvents watcher), UI (NSStatusItem + SwiftUI popover + preferences window). CLI tool for hook integration and scripting.

**Tech Stack:** Swift, SwiftUI, SwiftPM, NSStatusItem, FSEvents, Accessibility API, UserNotifications

**Spec:** `docs/superpowers/specs/2026-03-10-agentping-design.md`

---

## Chunk 1: Project Scaffold and Session Model

### Task 1: Initialize Swift Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/AgentPing/AgentPingApp.swift`
- Create: `Sources/AgentPingCLI/main.swift`

- [ ] **Step 1: Create Package.swift with two targets**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentPing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentPing", targets: ["AgentPing"]),
        .executable(name: "agentping", targets: ["AgentPingCLI"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AgentPing",
            dependencies: ["AgentPingCore"],
            path: "Sources/AgentPing"
        ),
        .executableTarget(
            name: "AgentPingCLI",
            dependencies: ["AgentPingCore"],
            path: "Sources/AgentPingCLI"
        ),
        .target(
            name: "AgentPingCore",
            path: "Sources/AgentPingCore"
        ),
        .testTarget(
            name: "AgentPingCoreTests",
            dependencies: ["AgentPingCore"],
            path: "Tests/AgentPingCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create minimal app entry point**

```swift
// Sources/AgentPing/AgentPingApp.swift
import SwiftUI

@main
struct AgentPingApp: App {
    var body: some Scene {
        MenuBarExtra("AgentPing", systemImage: "circle.grid.2x2") {
            Text("AgentPing running")
        }
        Settings {
            Text("Preferences")
        }
    }
}
```

- [ ] **Step 3: Create minimal CLI entry point**

```swift
// Sources/AgentPingCLI/main.swift
import Foundation
import AgentPingCore

print("agentping CLI")
```

- [ ] **Step 4: Create AgentPingCore placeholder**

```swift
// Sources/AgentPingCore/AgentPingCore.swift
import Foundation
```

- [ ] **Step 5: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Build succeeds with no errors

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "feat: initialize Swift package with app, CLI, and core targets"
```

---

### Task 2: Session Model

**Files:**
- Create: `Sources/AgentPingCore/Models/Session.swift`
- Create: `Tests/AgentPingCoreTests/SessionTests.swift`

- [ ] **Step 1: Write failing test for Session model**

```swift
// Tests/AgentPingCoreTests/SessionTests.swift
import XCTest
@testable import AgentPingCore

final class SessionTests: XCTestCase {
    func testSessionDecoding() throws {
        let json = """
        {
            "id": "session-abc123",
            "name": "Backend Refactor",
            "status": "running",
            "app": "vscode",
            "pid": 12345,
            "cwd": "/Users/eric/project",
            "startedAt": "2026-03-10T10:00:00Z",
            "lastEventAt": "2026-03-10T10:14:22Z",
            "notifications": true
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder.agentPing.decode(Session.self, from: json)
        XCTAssertEqual(session.id, "session-abc123")
        XCTAssertEqual(session.name, "Backend Refactor")
        XCTAssertEqual(session.status, .running)
        XCTAssertEqual(session.app, "vscode")
        XCTAssertEqual(session.pid, 12345)
        XCTAssertTrue(session.notifications)
    }

    func testSessionEncoding() throws {
        let session = Session(
            id: "test-1",
            name: "Test",
            status: .running,
            app: "ghostty",
            pid: 999,
            cwd: "/tmp",
            startedAt: Date(),
            lastEventAt: Date(),
            notifications: true
        )
        let data = try JSONEncoder.agentPing.encode(session)
        let decoded = try JSONDecoder.agentPing.decode(Session.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.status, .running)
    }

    func testAllStatusValues() {
        let cases: [SessionStatus] = [.running, .needsInput, .idle, .done, .error, .unavailable]
        for status in cases {
            XCTAssertNotNil(status.rawValue)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: FAIL -- Session type not found

- [ ] **Step 3: Implement Session model**

```swift
// Sources/AgentPingCore/Models/Session.swift
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
        costUsd: Double? = nil
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/Models/ Tests/
git commit -m "feat: add Session model with JSON coding and status enum"
```

---

### Task 3: Session Store (file-based persistence)

**Files:**
- Create: `Sources/AgentPingCore/Store/SessionStore.swift`
- Create: `Tests/AgentPingCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Write failing tests for SessionStore**

```swift
// Tests/AgentPingCoreTests/SessionStoreTests.swift
import XCTest
@testable import AgentPingCore

final class SessionStoreTests: XCTestCase {
    var store: SessionStore!
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-test-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWriteAndReadSession() throws {
        let session = Session(id: "test-1", name: "Test", status: .running, app: "ghostty", pid: 100, cwd: "/tmp", startedAt: Date(), lastEventAt: Date(), notifications: true)
        try store.write(session)

        let loaded = try store.read(id: "test-1")
        XCTAssertEqual(loaded?.id, "test-1")
        XCTAssertEqual(loaded?.status, .running)
    }

    func testListSessions() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .needsInput)
        try store.write(s1)
        try store.write(s2)

        let all = try store.listAll()
        XCTAssertEqual(all.count, 2)
    }

    func testDeleteSession() throws {
        let session = Session(id: "delete-me", status: .done)
        try store.write(session)
        try store.delete(id: "delete-me")
        let loaded = try store.read(id: "delete-me")
        XCTAssertNil(loaded)
    }

    func testDeleteUnavailable() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .unavailable)
        let s3 = Session(id: "s3", status: .unavailable)
        try store.write(s1)
        try store.write(s2)
        try store.write(s3)

        let deleted = try store.deleteUnavailable()
        XCTAssertEqual(deleted, 2)

        let remaining = try store.listAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, "s1")
    }

    func testCreatesDirectoryIfMissing() throws {
        let session = Session(id: "auto-dir", status: .idle)
        try store.write(session)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: FAIL -- SessionStore not found

- [ ] **Step 3: Implement SessionStore**

```swift
// Sources/AgentPingCore/Store/SessionStore.swift
import Foundation

public final class SessionStore {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentping/sessions")
    }

    private func filePath(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func ensureDirectory() throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
            return try? JSONDecoder.agentPing.decode(Session.self, from: data)
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: All SessionStore tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/Store/ Tests/
git commit -m "feat: add SessionStore for file-based session persistence"
```

---

## Chunk 2: Process Scanner and Session Manager

### Task 4: Process Scanner

**Files:**
- Create: `Sources/AgentPingCore/Scanner/ProcessScanner.swift`
- Create: `Tests/AgentPingCoreTests/ProcessScannerTests.swift`

- [ ] **Step 1: Write test for process info parsing**

```swift
// Tests/AgentPingCoreTests/ProcessScannerTests.swift
import XCTest
@testable import AgentPingCore

final class ProcessScannerTests: XCTestCase {
    func testParseProcessInfo() {
        // Test parsing a ps output line
        let line = "  12345  67890 /usr/local/bin/claude"
        let info = ProcessInfo.parse(psLine: line)
        XCTAssertEqual(info?.pid, 12345)
        XCTAssertEqual(info?.ppid, 67890)
        XCTAssertTrue(info?.command.contains("claude") ?? false)
    }

    func testParseInvalidLine() {
        let info = ProcessInfo.parse(psLine: "not a valid line")
        XCTAssertNil(info)
    }

    func testDetectAppFromProcessName() {
        XCTAssertEqual(ProcessScanner.detectApp(from: "Ghostty"), "ghostty")
        XCTAssertEqual(ProcessScanner.detectApp(from: "Code Helper (Plugin)"), "vscode")
        XCTAssertEqual(ProcessScanner.detectApp(from: "Terminal"), "terminal")
        XCTAssertEqual(ProcessScanner.detectApp(from: "iTerm2"), "iterm")
        XCTAssertEqual(ProcessScanner.detectApp(from: "unknown-app"), "unknown-app")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: FAIL -- ProcessInfo, ProcessScanner not found

- [ ] **Step 3: Implement ProcessScanner**

```swift
// Sources/AgentPingCore/Scanner/ProcessScanner.swift
import Foundation

public struct ProcessInfo {
    public let pid: Int
    public let ppid: Int
    public let command: String

    public static func parse(psLine: String) -> ProcessInfo? {
        let trimmed = psLine.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let pid = Int(parts[0]),
              let ppid = Int(parts[1]) else { return nil }
        return ProcessInfo(pid: pid, ppid: ppid, command: String(parts[2]))
    }
}

public final class ProcessScanner {
    public init() {}

    public static let appNameMap: [String: String] = [
        "Code Helper (Plugin)": "vscode",
        "Code Helper": "vscode",
        "Electron": "vscode",
        "Ghostty": "ghostty",
        "Terminal": "terminal",
        "iTerm2": "iterm",
        "Alacritty": "alacritty",
        "kitty": "kitty",
        "WezTerm": "wezterm",
        "tmux": "tmux",
    ]

    public static func detectApp(from processName: String) -> String {
        appNameMap[processName] ?? processName.lowercased()
    }

    /// Scan for running claude processes and return basic info
    public func scan() -> [ProcessInfo] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,ppid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            return output.components(separatedBy: "\n")
                .compactMap { ProcessInfo.parse(psLine: $0) }
                .filter { $0.command.contains("claude") }
        } catch {
            return []
        }
    }

    /// Walk process tree to find parent app name
    public func findParentApp(pid: Int) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "pid,ppid,comm", "-p", "\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let lines = output.components(separatedBy: "\n")
            guard let info = lines.dropFirst().compactMap({ ProcessInfo.parse(psLine: $0) }).first else {
                return nil
            }

            // If parent is launchd (pid 1) or self, we've gone too far
            if info.ppid <= 1 { return Self.detectApp(from: info.command) }

            // Recurse up the tree
            return findParentApp(pid: info.ppid) ?? Self.detectApp(from: info.command)
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: All ProcessScanner tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/Scanner/ Tests/
git commit -m "feat: add ProcessScanner for discovering claude processes"
```

---

### Task 5: SessionManager (state coordination)

**Files:**
- Create: `Sources/AgentPingCore/Manager/SessionManager.swift`
- Create: `Tests/AgentPingCoreTests/SessionManagerTests.swift`

- [ ] **Step 1: Write failing tests for SessionManager**

```swift
// Tests/AgentPingCoreTests/SessionManagerTests.swift
import XCTest
@testable import AgentPingCore

final class SessionManagerTests: XCTestCase {
    var manager: SessionManager!
    var store: SessionStore!
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-mgr-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
        manager = SessionManager(store: store)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadSessions() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .needsInput)
        try store.write(s1)
        try store.write(s2)

        manager.reload()
        XCTAssertEqual(manager.sessions.count, 2)
    }

    func testActiveSessions() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .done)
        let s3 = Session(id: "s3", status: .needsInput)
        try store.write(s1)
        try store.write(s2)
        try store.write(s3)

        manager.reload()
        XCTAssertEqual(manager.activeSessions.count, 2)
    }

    func testNeedsInputCount() throws {
        let s1 = Session(id: "s1", status: .running)
        let s2 = Session(id: "s2", status: .needsInput)
        let s3 = Session(id: "s3", status: .needsInput)
        try store.write(s1)
        try store.write(s2)
        try store.write(s3)

        manager.reload()
        XCTAssertEqual(manager.needsInputCount, 2)
    }

    func testUnavailableCount() throws {
        let s1 = Session(id: "s1", status: .unavailable)
        let s2 = Session(id: "s2", status: .running)
        try store.write(s1)
        try store.write(s2)

        manager.reload()
        XCTAssertEqual(manager.unavailableCount, 1)
    }

    func testClearUnavailable() throws {
        let s1 = Session(id: "s1", status: .unavailable)
        let s2 = Session(id: "s2", status: .running)
        try store.write(s1)
        try store.write(s2)

        manager.reload()
        manager.clearUnavailable()
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions.first?.id, "s2")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: FAIL -- SessionManager not found

- [ ] **Step 3: Implement SessionManager**

```swift
// Sources/AgentPingCore/Manager/SessionManager.swift
import Foundation
import Combine

public final class SessionManager: ObservableObject {
    @Published public private(set) var sessions: [Session] = []

    private let store: SessionStore

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
        } catch {
            sessions = []
        }
    }

    public func clearUnavailable() {
        do {
            try store.deleteUnavailable()
            reload()
        } catch {}
    }

    public func updateSession(_ session: Session) {
        do {
            try store.write(session)
            reload()
        } catch {}
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: All SessionManager tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentPingCore/Manager/ Tests/
git commit -m "feat: add SessionManager for state coordination"
```

---

## Chunk 3: CLI Tool

### Task 6: CLI Report Command

**Files:**
- Create: `Sources/AgentPingCore/CLI/ReportCommand.swift`
- Modify: `Sources/AgentPingCLI/main.swift`
- Create: `Tests/AgentPingCoreTests/ReportCommandTests.swift`

- [ ] **Step 1: Add ArgumentParser dependency to Package.swift**

Add to dependencies:
```swift
.package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
```

Add to AgentPingCLI target dependencies:
```swift
.product(name: "ArgumentParser", package: "swift-argument-parser"),
```

Add to AgentPingCore target dependencies:
```swift
.product(name: "ArgumentParser", package: "swift-argument-parser"),
```

- [ ] **Step 2: Write failing test for report command logic**

```swift
// Tests/AgentPingCoreTests/ReportCommandTests.swift
import XCTest
@testable import AgentPingCore

final class ReportCommandTests: XCTestCase {
    var store: SessionStore!
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentping-cli-\(UUID().uuidString)")
        store = SessionStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReportCreatesNewSession() throws {
        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "new-1", event: "tool-use", name: "My Task", file: "app.ts")

        let session = try store.read(id: "new-1")
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.name, "My Task")
        XCTAssertEqual(session?.status, .running)
        XCTAssertEqual(session?.file, "app.ts")
    }

    func testReportUpdatesExistingSession() throws {
        let existing = Session(id: "exist-1", name: "Old Name", status: .running)
        try store.write(existing)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "exist-1", event: "needs-input", name: nil, file: "new.ts")

        let session = try store.read(id: "exist-1")
        XCTAssertEqual(session?.name, "Old Name") // name not overwritten
        XCTAssertEqual(session?.status, .needsInput)
        XCTAssertEqual(session?.file, "new.ts")
    }

    func testReportStoppedEvent() throws {
        let existing = Session(id: "stop-1", status: .running)
        try store.write(existing)

        let handler = ReportHandler(store: store)
        try handler.handle(sessionId: "stop-1", event: "stopped", name: nil, file: nil)

        let session = try store.read(id: "stop-1")
        XCTAssertEqual(session?.status, .done)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: FAIL -- ReportHandler not found

- [ ] **Step 4: Implement ReportHandler**

```swift
// Sources/AgentPingCore/CLI/ReportHandler.swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/eric.er/agentping && swift test`
Expected: All ReportCommand tests PASS

- [ ] **Step 6: Wire up CLI main with ArgumentParser**

```swift
// Sources/AgentPingCLI/main.swift
import ArgumentParser
import AgentPingCore

struct AgentPingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentping",
        abstract: "AgentPing CLI - manage Claude Code sessions",
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
        let store = SessionStore()
        let sessions = try store.listAll()
        let running = sessions.filter { $0.status == .running }.count
        let needsInput = sessions.filter { $0.status == .needsInput }.count
        let idle = sessions.filter { $0.status == .idle }.count
        print("\(running) running, \(needsInput) needs input, \(idle) idle")
    }
}

AgentPingCommand.main()
```

- [ ] **Step 7: Verify CLI builds and runs**

Run: `cd /Users/eric.er/agentping && swift build && .build/debug/agentping --help`
Expected: Shows help text with report, list, status subcommands

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/AgentPingCore/CLI/ Sources/AgentPingCLI/ Tests/
git commit -m "feat: add CLI tool with report, list, and status commands"
```

---

## Chunk 4: Menu Bar UI

### Task 7: Menu Bar Icon with Badge

**Files:**
- Modify: `Sources/AgentPing/AgentPingApp.swift`
- Create: `Sources/AgentPing/Views/StatusItemController.swift`

- [ ] **Step 1: Implement StatusItemController with NSStatusItem**

```swift
// Sources/AgentPing/Views/StatusItemController.swift
import AppKit
import SwiftUI
import AgentPingCore
import Combine

final class StatusItemController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    init(manager: SessionManager) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(manager: manager)
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "AgentPing")
            button.action = #selector(togglePopover)
            button.target = self
        }

        manager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateIcon(sessions: sessions)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(sessions: [Session]) {
        guard let button = statusItem.button else { return }

        let active = sessions.filter { [.running, .needsInput, .idle].contains($0.status) }
        let needsInput = sessions.contains { $0.status == .needsInput }

        let title = active.isEmpty ? "" : " \(active.count)"
        button.title = title

        // Use filled icon when sessions need input
        let symbolName = needsInput ? "circle.grid.2x2.fill" : "circle.grid.2x2"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentPing")

        // Red badge dot overlay via attributed title
        if needsInput {
            let attr = NSMutableAttributedString(string: title)
            attr.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: attr.length))
            button.attributedTitle = attr
        } else {
            button.attributedTitle = nil
            button.title = title
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
```

- [ ] **Step 2: Update app entry point to use controller**

```swift
// Sources/AgentPing/AgentPingApp.swift
import SwiftUI
import AgentPingCore

@main
struct AgentPingApp: App {
    @StateObject private var manager = SessionManager()
    @State private var controller: StatusItemController?

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }

    init() {
        // Hide dock icon
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    // StatusItemController is created in applicationDidFinishLaunching via AppDelegate
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusItemController?
    let manager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusItemController(manager: manager)
        manager.reload()
        startPeriodicScan()
    }

    private func startPeriodicScan() {
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.manager.reload()
        }
    }
}
```

Note: The exact app lifecycle wiring may need adjustment between `@main` App protocol and AppDelegate. The implementation agent should choose the cleanest approach for macOS 14.

- [ ] **Step 3: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Builds successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPing/
git commit -m "feat: add menu bar icon with active session count and needs-input badge"
```

---

### Task 8: Popover View

**Files:**
- Create: `Sources/AgentPing/Views/PopoverView.swift`
- Create: `Sources/AgentPing/Views/SessionRowView.swift`

- [ ] **Step 1: Implement SessionRowView**

```swift
// Sources/AgentPing/Views/SessionRowView.swift
import SwiftUI
import AgentPingCore

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name ?? "Unnamed Session")
                    .font(.system(.body, design: .monospaced, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("→ \(session.app?.uppercased() ?? "UNKNOWN")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if let file = session.file {
                        Text(file)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if session.status == .needsInput {
                Text("INPUT")
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: RoundedRectangle(cornerRadius: 3))
            } else {
                Text(elapsedTime)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .primary
        case .needsInput: return .red
        case .idle: return .secondary
        case .done: return .green
        case .error: return .orange
        case .unavailable: return .gray
        }
    }

    private var elapsedTime: String {
        let interval = Date().timeIntervalSince(session.startedAt)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 2: Implement PopoverView**

```swift
// Sources/AgentPing/Views/PopoverView.swift
import SwiftUI
import AgentPingCore

enum SessionTab: String, CaseIterable {
    case running = "Running"
    case history = "History"
}

struct PopoverView: View {
    @ObservedObject var manager: SessionManager
    @State private var selectedTab: SessionTab = .running

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AGENTPING")
                    .font(.system(.headline, design: .monospaced, weight: .bold))
                Spacer()
                Text("\(manager.activeSessions.count) active")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(SessionTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Session list
            ScrollView {
                LazyVStack(spacing: 0) {
                    let sessions = selectedTab == .running
                        ? manager.activeSessions
                        : manager.historySessions

                    if sessions.isEmpty {
                        Text("No \(selectedTab.rawValue.lowercased()) sessions")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(sessions) { session in
                            SessionRowView(session: session)
                                .onTapGesture {
                                    jumpToWindow(session: session)
                                }

                            if session.id != sessions.last?.id {
                                Divider().padding(.leading, 24)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider()

            // Footer
            VStack(spacing: 4) {
                if manager.unavailableCount > 0 {
                    Button {
                        manager.clearUnavailable()
                    } label: {
                        Text("Clear Unavailable (\(manager.unavailableCount))")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private func jumpToWindow(session: Session) {
        // Window jumping will be implemented in Task 9
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Builds successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPing/Views/
git commit -m "feat: add popover UI with session list, tabs, and compact rows"
```

---

## Chunk 5: Window Jumping and Notifications

### Task 9: Window Jumping via Accessibility API

**Files:**
- Create: `Sources/AgentPingCore/WindowJumper/WindowJumper.swift`

- [ ] **Step 1: Implement WindowJumper**

```swift
// Sources/AgentPingCore/WindowJumper/WindowJumper.swift
import AppKit
import ApplicationServices

public final class WindowJumper {
    public init() {}

    /// Attempt to focus the window for a given session
    public func jumpTo(session: Session) -> Bool {
        guard let appName = session.app else { return false }

        // Find the running application
        let apps = NSWorkspace.shared.runningApplications
        let app = apps.first { runningApp in
            let name = runningApp.localizedName?.lowercased() ?? ""
            return name.contains(appName) ||
                   ProcessScanner.appNameMap.values.contains(where: { $0 == appName && name.contains($0) })
        }

        // Fallback: match by PID's parent app
        let targetApp = app ?? findAppByPid(session.pid)

        guard let targetApp else { return false }

        // Activate the app
        targetApp.activate()

        // Try to raise the specific window via Accessibility API
        if let pid = session.pid {
            raiseWindowForPid(pid, in: targetApp)
        }

        return true
    }

    private func findAppByPid(_ pid: Int?) -> NSRunningApplication? {
        guard let pid else { return nil }

        // Walk up the process tree to find an app
        var currentPid = pid
        for _ in 0..<10 { // max depth
            if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)),
               app.activationPolicy == .regular {
                return app
            }
            // Get parent PID
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(currentPid)]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let ppid = Int(info.kp_eproc.e_ppid)
            if ppid <= 1 { break }
            currentPid = ppid
        }
        return nil
    }

    private func raiseWindowForPid(_ pid: Int, in app: NSRunningApplication) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        // Raise the first window (best effort)
        if let window = windows.first {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
        }
    }
}
```

- [ ] **Step 2: Wire into PopoverView tap action**

Update `jumpToWindow` in PopoverView.swift:

```swift
private func jumpToWindow(session: Session) {
    let jumper = WindowJumper()
    _ = jumper.jumpTo(session: session)
}
```

- [ ] **Step 3: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Builds (Accessibility API requires runtime permission, can't test in unit tests)

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPingCore/WindowJumper/ Sources/AgentPing/Views/PopoverView.swift
git commit -m "feat: add window jumping via Accessibility API"
```

---

### Task 10: Notifications

**Files:**
- Create: `Sources/AgentPing/Notifications/NotificationManager.swift`

- [ ] **Step 1: Implement NotificationManager**

```swift
// Sources/AgentPing/Notifications/NotificationManager.swift
import UserNotifications
import AgentPingCore

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var onSessionTapped: ((String) -> Void)?

    func setup(onSessionTapped: @escaping (String) -> Void) {
        self.onSessionTapped = onSessionTapped
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendNeedsInput(session: Session) {
        guard session.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = "Agent needs input"
        content.body = "\(session.name ?? "Session") in \(session.app?.uppercased() ?? "unknown") is waiting for you"
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "needs-input-\(session.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let sessionId = response.notification.request.content.userInfo["sessionId"] as? String {
            onSessionTapped?(sessionId)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
```

- [ ] **Step 2: Integrate with SessionManager to trigger notifications on status change**

Add to AppDelegate's `applicationDidFinishLaunching`:

```swift
NotificationManager.shared.setup { [weak self] sessionId in
    guard let session = self?.manager.sessions.first(where: { $0.id == sessionId }) else { return }
    let jumper = WindowJumper()
    _ = jumper.jumpTo(session: session)
}
```

- [ ] **Step 3: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Builds successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPing/Notifications/
git commit -m "feat: add macOS notifications for sessions needing input"
```

---

## Chunk 6: Preferences and FSEvents Watcher

### Task 11: FSEvents Directory Watcher

**Files:**
- Create: `Sources/AgentPingCore/Watcher/DirectoryWatcher.swift`

- [ ] **Step 1: Implement DirectoryWatcher**

```swift
// Sources/AgentPingCore/Watcher/DirectoryWatcher.swift
import Foundation

public final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let onChange: () -> Void

    public init(path: String? = nil, onChange: @escaping () -> Void) {
        self.path = path ?? NSHomeDirectory() + "/.agentping/sessions"
        self.onChange = onChange
    }

    public func start() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}
```

- [ ] **Step 2: Integrate with AppDelegate**

Wire DirectoryWatcher to call `manager.reload()` on changes.

- [ ] **Step 3: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Builds successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPingCore/Watcher/
git commit -m "feat: add FSEvents directory watcher for live session updates"
```

---

### Task 12: Preferences Window

**Files:**
- Create: `Sources/AgentPing/Views/PreferencesView.swift`

- [ ] **Step 1: Implement PreferencesView**

```swift
// Sources/AgentPing/Views/PreferencesView.swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("scanInterval") private var scanInterval = 10.0
    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }

                Picker("Scan interval", selection: $scanInterval) {
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Text("Per-session notifications can be toggled from the session context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Toggle("Show cost per session", isOn: $costTrackingEnabled)
            }

            Section("Hooks") {
                Text("Add these hooks to ~/.claude/settings.json to enable rich session tracking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Copy Hook Config to Clipboard") {
                    copyHookConfig()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 360)
    }

    private func copyHookConfig() {
        let config = """
        {
          "hooks": {
            "PostToolUse": [{"command": "agentping report --session $CLAUDE_SESSION_ID --event tool-use"}],
            "Stop": [{"command": "agentping report --session $CLAUDE_SESSION_ID --event stopped"}],
            "Notification": [{"command": "agentping report --session $CLAUDE_SESSION_ID --event needs-input"}]
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd /Users/eric.er/agentping && swift build`
Expected: Builds successfully

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentPing/Views/PreferencesView.swift
git commit -m "feat: add preferences window with launch-at-login, notifications, and hook helper"
```

---

## Chunk 7: Integration and Polish

### Task 13: Wire Everything Together in AppDelegate

**Files:**
- Modify: `Sources/AgentPing/AgentPingApp.swift`

- [ ] **Step 1: Finalize AppDelegate wiring**

Ensure AppDelegate creates and connects:
1. SessionManager
2. StatusItemController (with popover)
3. DirectoryWatcher (triggers manager.reload)
4. ProcessScanner (periodic timer)
5. NotificationManager (listens for status changes)

The app should:
- Start with no dock icon (`NSApplication.shared.setActivationPolicy(.accessory)`)
- Show menu bar icon immediately
- Begin scanning for sessions
- Watch `~/.agentping/sessions/` for hook updates

- [ ] **Step 2: Test manually**

Run: `cd /Users/eric.er/agentping && swift build && .build/debug/AgentPing`
Expected: Menu bar icon appears, popover opens on click, shows empty state

- [ ] **Step 3: Test with CLI**

Run: `.build/debug/agentping report --session test-1 --event tool-use --name "Test Session"`
Expected: Session appears in popover within seconds

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentPing/
git commit -m "feat: wire all components together in app lifecycle"
```

---

### Task 14: Info.plist and App Configuration

**Files:**
- Create: `Sources/AgentPing/Info.plist`

- [ ] **Step 1: Create Info.plist for LSUIElement (no dock icon)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>AgentPing</string>
    <key>CFBundleIdentifier</key>
    <string>com.agentping.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>AgentPing needs accessibility access to focus terminal windows when you click on a session.</string>
</dict>
</plist>
```

- [ ] **Step 2: Commit**

```bash
git add Sources/AgentPing/Info.plist
git commit -m "feat: add Info.plist with LSUIElement and accessibility usage description"
```

---

### Task 15: Add .gitignore and README

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```
.build/
.swiftpm/
*.xcodeproj
*.xcworkspace
DerivedData/
.DS_Store
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore for Swift project"
```
