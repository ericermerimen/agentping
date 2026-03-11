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
