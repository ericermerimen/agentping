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
