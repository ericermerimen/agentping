import Foundation

final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var updateURL: URL?
    @Published var isChecking = false
    @Published var error: String?

    static let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
    }()

    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return Self.compareVersions(latest, isNewerThan: Self.currentVersion)
    }

    func check() {
        guard !isChecking else { return }
        isChecking = true
        error = nil

        let url = URL(string: "https://api.github.com/repos/ericermerimen/agentping/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, err in
            DispatchQueue.main.async {
                self?.isChecking = false

                if let err {
                    self?.error = err.localizedDescription
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self?.error = "Could not parse release info"
                    return
                }

                let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                self?.latestVersion = version
                if let htmlURL = json["html_url"] as? String {
                    self?.updateURL = URL(string: htmlURL)
                }
            }
        }.resume()
    }

    /// Compare two semver-like strings. Returns true if `a` is newer than `b`.
    /// Handles versions like "0.6.0", "0.7.0-beta.1". Stable > pre-release for same base.
    static func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = splitVersion(a)
        let partsB = splitVersion(b)

        // Compare numeric parts
        let maxLen = max(partsA.numbers.count, partsB.numbers.count)
        for i in 0..<maxLen {
            let na = i < partsA.numbers.count ? partsA.numbers[i] : 0
            let nb = i < partsB.numbers.count ? partsB.numbers[i] : 0
            if na != nb { return na > nb }
        }

        // Same base version: stable (no pre-release) is newer than pre-release
        if partsA.prerelease == nil && partsB.prerelease != nil { return true }
        if partsA.prerelease != nil && partsB.prerelease == nil { return false }

        // Both have pre-release: compare lexicographically
        if let preA = partsA.prerelease, let preB = partsB.prerelease {
            return preA > preB
        }

        return false
    }

    private static func splitVersion(_ v: String) -> (numbers: [Int], prerelease: String?) {
        let parts = v.split(separator: "-", maxSplits: 1)
        let numbers = parts[0].split(separator: ".").compactMap { Int($0) }
        let prerelease = parts.count > 1 ? String(parts[1]) : nil
        return (numbers, prerelease)
    }
}
