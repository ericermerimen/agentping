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
}
