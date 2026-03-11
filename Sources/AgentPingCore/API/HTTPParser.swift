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
