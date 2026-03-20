import XCTest
@testable import AgentPingCore

final class SessionDisplayTests: XCTestCase {

    // MARK: - isAttention

    func testIsAttention_needsInput() {
        let s = Session(id: "1", status: .needsInput)
        XCTAssertTrue(s.isAttention)
    }

    func testIsAttention_error() {
        let s = Session(id: "2", status: .error)
        XCTAssertTrue(s.isAttention)
    }

    func testIsAttention_freshIdle() {
        let s = Session(id: "3", status: .idle, lastEventAt: Date())
        XCTAssertTrue(s.isFreshIdle)
        XCTAssertTrue(s.isAttention)
    }

    func testIsAttention_running() {
        let s = Session(id: "4", status: .running)
        XCTAssertFalse(s.isAttention)
    }

    func testIsAttention_done() {
        let s = Session(id: "5", status: .done)
        XCTAssertFalse(s.isAttention)
    }

    func testIsAttention_reviewedIdle() {
        let s = Session(id: "6", status: .idle, lastEventAt: Date().addingTimeInterval(-10), reviewedAt: Date())
        XCTAssertFalse(s.isFreshIdle)
        XCTAssertFalse(s.isAttention)
    }

    // MARK: - projectName

    func testProjectName_fromCwd() {
        let s = Session(id: "1", cwd: "/Users/eric/myproject")
        XCTAssertEqual(s.projectName, "myproject")
    }

    func testProjectName_homeCwd_fallsBackToTask() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "2", cwd: home, taskDescription: "Fix the bug")
        XCTAssertEqual(s.projectName, "Fix the bug")
    }

    func testProjectName_homeCwd_noTask_fallsBackToName() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "3", name: "My Session", cwd: home)
        XCTAssertEqual(s.projectName, "My Session")
    }

    func testProjectName_noCwd_noTask_noName() {
        let s = Session(id: "4")
        XCTAssertEqual(s.projectName, "Unnamed")
    }

    func testProjectName_noCwd_withTask() {
        let s = Session(id: "5", taskDescription: "Deploy server")
        XCTAssertEqual(s.projectName, "Deploy server")
    }

    // MARK: - displayPath

    func testDisplayPath_underHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "1", cwd: home + "/projects/app")
        XCTAssertEqual(s.displayPath, "~/projects/app")
    }

    func testDisplayPath_outsideHome() {
        let s = Session(id: "2", cwd: "/opt/server/app")
        XCTAssertEqual(s.displayPath, "/opt/server/app")
    }

    func testDisplayPath_noCwd() {
        let s = Session(id: "3")
        XCTAssertEqual(s.displayPath, "")
    }

    func testDisplayPath_emptyCwd() {
        let s = Session(id: "4", cwd: "")
        XCTAssertEqual(s.displayPath, "")
    }

    // MARK: - subtitle

    func testSubtitle_homeCwd() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "1", cwd: home)
        XCTAssertEqual(s.subtitle, "~")
    }

    func testSubtitle_withTask() {
        let s = Session(id: "2", cwd: "/Users/eric/project", taskDescription: "Working on tests")
        XCTAssertEqual(s.subtitle, "Working on tests")
    }

    func testSubtitle_noTask_hasCwd() {
        let s = Session(id: "3", cwd: "/opt/server")
        XCTAssertEqual(s.subtitle, "/opt/server")
    }

    func testSubtitle_noCwd_noTask() {
        let s = Session(id: "4")
        XCTAssertNil(s.subtitle)
    }

    // MARK: - isHomeCwd

    func testIsHomeCwd_exactMatch() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "1", cwd: home)
        XCTAssertTrue(s.isHomeCwd)
    }

    func testIsHomeCwd_withTrailingSlash() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "2", cwd: home + "/")
        XCTAssertTrue(s.isHomeCwd)
    }

    func testIsHomeCwd_subdirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = Session(id: "3", cwd: home + "/projects")
        XCTAssertFalse(s.isHomeCwd)
    }

    func testIsHomeCwd_nil() {
        let s = Session(id: "4")
        XCTAssertFalse(s.isHomeCwd)
    }

    // MARK: - idleElapsed

    func testIdleElapsed_justNow() {
        let s = Session(id: "1", lastEventAt: Date())
        XCTAssertEqual(s.idleElapsed(now: Date()), "idle")
    }

    func testIdleElapsed_minutes() {
        let s = Session(id: "2", lastEventAt: Date().addingTimeInterval(-300))
        XCTAssertEqual(s.idleElapsed(now: Date()), "idle 5m")
    }

    func testIdleElapsed_hours() {
        let s = Session(id: "3", lastEventAt: Date().addingTimeInterval(-7200))
        XCTAssertEqual(s.idleElapsed(now: Date()), "idle 2h")
    }

    func testIdleElapsed_futureDate() {
        let s = Session(id: "4", lastEventAt: Date().addingTimeInterval(100))
        XCTAssertEqual(s.idleElapsed(now: Date()), "idle")
    }

    // MARK: - isFreshIdle

    func testIsFreshIdle_idleNoReview() {
        let s = Session(id: "1", status: .idle, lastEventAt: Date())
        XCTAssertTrue(s.isFreshIdle)
    }

    func testIsFreshIdle_idleReviewedBefore() {
        let s = Session(id: "2", status: .idle, lastEventAt: Date(), reviewedAt: Date().addingTimeInterval(-10))
        XCTAssertTrue(s.isFreshIdle)
    }

    func testIsFreshIdle_idleReviewedAfter() {
        let s = Session(id: "3", status: .idle, lastEventAt: Date().addingTimeInterval(-10), reviewedAt: Date())
        XCTAssertFalse(s.isFreshIdle)
    }

    func testIsFreshIdle_running() {
        let s = Session(id: "4", status: .running)
        XCTAssertFalse(s.isFreshIdle)
    }
}
