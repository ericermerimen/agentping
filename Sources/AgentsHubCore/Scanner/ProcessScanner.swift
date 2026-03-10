import Foundation

public struct AgentProcessInfo {
    public let pid: Int
    public let ppid: Int
    public let command: String

    public static func parse(psLine: String) -> AgentProcessInfo? {
        let trimmed = psLine.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let pid = Int(parts[0]),
              let ppid = Int(parts[1]) else { return nil }
        return AgentProcessInfo(pid: pid, ppid: ppid, command: String(parts[2]))
    }
}

public final class ProcessScanner {
    public init() {}

    public static let appNameMap: [String: String] = [
        "Code Helper (Plugin)": "vscode",
        "Code Helper": "vscode",
        "Electron": "vscode",
        "Ghostty": "ghostty",
        "Terminal": "terminal",
        "iTerm2": "iterm",
        "Alacritty": "alacritty",
        "kitty": "kitty",
        "WezTerm": "wezterm",
        "tmux": "tmux",
    ]

    public static func detectApp(from processName: String) -> String {
        appNameMap[processName] ?? processName.lowercased()
    }

    /// Scan for running claude processes and return basic info
    public func scan() -> [AgentProcessInfo] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid,ppid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            return output.components(separatedBy: "\n")
                .compactMap { AgentProcessInfo.parse(psLine: $0) }
                .filter { $0.command.contains("claude") }
        } catch {
            return []
        }
    }

    /// Walk process tree to find parent app name
    public func findParentApp(pid: Int) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "pid,ppid,comm", "-p", "\(pid)"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let lines = output.components(separatedBy: "\n")
            guard let info = lines.dropFirst().compactMap({ AgentProcessInfo.parse(psLine: $0) }).first else {
                return nil
            }

            // If parent is launchd (pid 1) or self, we've gone too far
            if info.ppid <= 1 { return Self.detectApp(from: info.command) }

            // Recurse up the tree
            return findParentApp(pid: info.ppid) ?? Self.detectApp(from: info.command)
        } catch {
            return nil
        }
    }
}
