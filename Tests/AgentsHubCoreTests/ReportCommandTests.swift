import XCTest
@testable import AgentsHubCore

final class ReportCommandTests: XCTestCase {
    var store: SessionStore!
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentshub-cli-\(UUID().uuidString)")
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
