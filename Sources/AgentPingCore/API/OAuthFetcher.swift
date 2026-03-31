import Foundation
import Security

/// Quota data fetched from the Anthropic OAuth usage API.
public struct UsageQuota: Codable, Equatable {
    public let sessionPercent: Double?    // five_hour percentage (0.0–1.0)
    public let weeklyPercent: Double?     // seven_day percentage (0.0–1.0)
    public let monthlySpend: Double?      // extra_usage monthly spend in USD
    public let fetchedAt: Date

    public init(sessionPercent: Double?, weeklyPercent: Double?, monthlySpend: Double?, fetchedAt: Date = Date()) {
        self.sessionPercent = sessionPercent
        self.weeklyPercent = weeklyPercent
        self.monthlySpend = monthlySpend
        self.fetchedAt = fetchedAt
    }
}

/// Fetches authoritative quota data from Anthropic's OAuth usage API.
///
/// Reads the OAuth token from macOS Keychain or ~/.claude/.credentials.json,
/// then calls the usage endpoint. Results are cached with a configurable TTL.
public actor OAuthFetcher {
    public static let shared = OAuthFetcher()

    private let urlSession: URLSession
    private var cachedQuota: UsageQuota?
    private var inflight: Task<UsageQuota?, Never>?

    /// Time-to-live for cached quota data (default 5 minutes).
    public var cacheTTL: TimeInterval = 300

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(session: URLSession = .shared) {
        self.urlSession = session
    }

    // MARK: - Public API

    /// Fetch quota, returning cached data if still fresh.
    /// Returns nil if no credentials are available or the API call fails.
    public func fetchQuota() async -> UsageQuota? {
        // Return cached result if still valid
        if let cached = cachedQuota, Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached
        }

        // Coalesce concurrent requests
        if let existing = inflight {
            return await existing.value
        }

        let task = Task<UsageQuota?, Never> {
            await self.doFetch()
        }
        inflight = task

        let result = await task.value
        cachedQuota = result
        inflight = nil
        return result
    }

    /// Invalidate the cache so the next call fetches fresh data.
    public func invalidateCache() {
        cachedQuota = nil
    }

    // MARK: - Token Resolution

    /// Read the OAuth access token. Tries Keychain first, then credential file.
    static func resolveToken() -> String? {
        if let token = readFromKeychain() { return token }
        if let token = readFromFile() { return token }
        return nil
    }

    /// Read token from macOS Keychain (service: "Claude Code-credentials").
    static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return extractToken(from: data)
    }

    /// Read token from ~/.claude/.credentials.json.
    static func readFromFile() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let credPath = home.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: credPath) else { return nil }
        return extractToken(from: data)
    }

    /// Parse JSON data to extract the accessToken field.
    private static func extractToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }

    // MARK: - Network

    private func doFetch() async -> UsageQuota? {
        guard let token = Self.resolveToken() else {
            print("[AgentPing] OAuth: no credentials found, skipping quota fetch")
            return nil
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                print("[AgentPing] OAuth: non-HTTP response")
                return nil
            }

            guard http.statusCode == 200 else {
                // 403 = token lacks user:profile scope (expected for some users)
                // 401 = invalid/expired token
                if http.statusCode == 403 || http.statusCode == 401 {
                    print("[AgentPing] OAuth: \(http.statusCode) -- token may lack required scope")
                } else {
                    print("[AgentPing] OAuth: HTTP \(http.statusCode)")
                }
                return nil
            }

            return parseUsageResponse(data)
        } catch {
            print("[AgentPing] OAuth: fetch failed -- \(error.localizedDescription)")
            return nil
        }
    }

    /// Parse the usage API response, tolerating missing or unexpected fields.
    private func parseUsageResponse(_ data: Data) -> UsageQuota? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[AgentPing] OAuth: failed to parse response JSON")
            return nil
        }

        let sessionPercent: Double? = {
            guard let fiveHour = json["five_hour"] as? [String: Any] else { return nil }
            return fiveHour["percentage"] as? Double
        }()

        let weeklyPercent: Double? = {
            guard let sevenDay = json["seven_day"] as? [String: Any] else { return nil }
            return sevenDay["percentage"] as? Double
        }()

        let monthlySpend: Double? = {
            guard let extra = json["extra_usage"] as? [String: Any] else { return nil }
            return extra["monthly_spend"] as? Double
        }()

        // Only return a quota if we got at least one useful field
        guard sessionPercent != nil || weeklyPercent != nil || monthlySpend != nil else {
            print("[AgentPing] OAuth: response had no usable quota fields")
            return nil
        }

        return UsageQuota(
            sessionPercent: sessionPercent,
            weeklyPercent: weeklyPercent,
            monthlySpend: monthlySpend
        )
    }
}
