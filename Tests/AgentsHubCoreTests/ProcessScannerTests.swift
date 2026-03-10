import XCTest
@testable import AgentsHubCore

final class ProcessScannerTests: XCTestCase {
    func testParseProcessInfo() {
        // Test parsing a ps output line
        let line = "  12345  67890 /usr/local/bin/claude"
        let info = AgentProcessInfo.parse(psLine: line)
        XCTAssertEqual(info?.pid, 12345)
        XCTAssertEqual(info?.ppid, 67890)
        XCTAssertTrue(info?.command.contains("claude") ?? false)
    }

    func testParseInvalidLine() {
        let info = AgentProcessInfo.parse(psLine: "not a valid line")
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
