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

    // MARK: - sanitizeId path traversal

    func testSanitizeId_normalId() {
        XCTAssertEqual(SessionStore.sanitizeId("abc-123"), "abc-123")
    }

    func testSanitizeId_pathTraversal() {
        let result = SessionStore.sanitizeId("../../etc/passwd")
        XCTAssertFalse(result.contains(".."))
        XCTAssertFalse(result.contains("/"))
    }

    func testSanitizeId_forwardSlash() {
        let result = SessionStore.sanitizeId("path/to/file")
        XCTAssertFalse(result.contains("/"))
    }

    func testSanitizeId_backslash() {
        let result = SessionStore.sanitizeId("path\\to\\file")
        XCTAssertFalse(result.contains("\\"))
    }

    func testSanitizeId_nullBytes() {
        let result = SessionStore.sanitizeId("abc\0def")
        XCTAssertFalse(result.contains("\0"))
    }

    func testSanitizeId_emptyString() {
        let result = SessionStore.sanitizeId("")
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result, "_invalid_")
    }
}
