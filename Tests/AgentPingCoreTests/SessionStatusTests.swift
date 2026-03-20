import XCTest
@testable import AgentPingCore

final class SessionStatusTests: XCTestCase {

    // MARK: - SessionStatus.from() subagent-stop preservation

    func testSubagentStop_preservesRunning() {
        let result = SessionStatus.from(event: "subagent-stop", current: .running)
        XCTAssertEqual(result, .running)
    }

    func testSubagentStop_preservesIdle() {
        let result = SessionStatus.from(event: "subagent-stop", current: .idle)
        XCTAssertEqual(result, .idle)
    }

    func testSubagentStop_preservesNeedsInput() {
        let result = SessionStatus.from(event: "subagent-stop", current: .needsInput)
        XCTAssertEqual(result, .needsInput)
    }

    func testSubagentStop_preservesDone() {
        let result = SessionStatus.from(event: "subagent-stop", current: .done)
        XCTAssertEqual(result, .done)
    }

    func testSubagentStop_preservesError() {
        let result = SessionStatus.from(event: "subagent-stop", current: .error)
        XCTAssertEqual(result, .error)
    }

    // MARK: - Other event mappings

    func testToolUse_returnsRunning() {
        XCTAssertEqual(SessionStatus.from(event: "tool-use", current: .idle), .running)
    }

    func testNeedsInput_returnsNeedsInput() {
        XCTAssertEqual(SessionStatus.from(event: "needs-input", current: .running), .needsInput)
    }

    func testStopped_fromRunning_returnsIdle() {
        XCTAssertEqual(SessionStatus.from(event: "stopped", current: .running), .idle)
    }

    func testStopped_fromNeedsInput_preservesNeedsInput() {
        XCTAssertEqual(SessionStatus.from(event: "stopped", current: .needsInput), .needsInput)
    }

    func testSessionEnd_returnsDone() {
        XCTAssertEqual(SessionStatus.from(event: "session-end", current: .running), .done)
    }

    func testError_returnsError() {
        XCTAssertEqual(SessionStatus.from(event: "error", current: .running), .error)
    }

    func testUnknownEvent_defaultsToRunning() {
        XCTAssertEqual(SessionStatus.from(event: "unknown-event", current: .idle), .running)
    }
}
