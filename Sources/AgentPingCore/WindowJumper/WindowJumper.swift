#if canImport(AppKit)
import AppKit
import ApplicationServices

public final class WindowJumper {
    public init() {}

    /// Bundle identifiers for common terminal apps
    private static let terminalBundleIds: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    /// Map normalized app names (from ProcessScanner) to bundle identifiers
    private static let appBundleIds: [String: [String]] = [
        "vscode": ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.VSCodium"],
        "cursor": ["com.todesktop.230313mzl4w4u92"],
        "windsurf": ["com.codeium.windsurf"],
        "trae": ["com.trae.app"],
        "zed": ["dev.zed.Zed"],
        "ghostty": ["com.mitchellh.ghostty"],
        "terminal": ["com.apple.Terminal"],
        "iterm": ["com.googlecode.iterm2"],
        "alacritty": ["io.alacritty"],
        "kitty": ["net.kovidgoyal.kitty"],
        "wezterm": ["com.github.wez.wezterm"],
    ]

    /// Attempt to focus the window for a given session
    public func jumpTo(session: Session) -> Bool {
        // Strategy 1: Use app name + pid if available (original path)
        if let appName = session.app {
            if let app = findRunningApp(named: appName) ?? findAppByPid(session.pid) {
                app.activate()
                if let pid = session.pid {
                    raiseWindowForPid(pid, in: app)
                } else if let cwd = session.cwd {
                    raiseWindowByCwd(cwd, in: app)
                }
                return true
            }
        }

        // Strategy 2: Use pid to walk up to parent app
        if let pid = session.pid, let app = findAppByPid(pid) {
            app.activate()
            raiseWindowForPid(pid, in: app)
            return true
        }

        // Strategy 3: Use cwd to find the terminal window whose title contains the directory
        if let cwd = session.cwd {
            if let (app, window) = findTerminalWindowByCwd(cwd) {
                app.activate()
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return true
            }

            // Strategy 4: Fall back to activating any running terminal app
            if let app = findAnyTerminalApp() {
                app.activate()
                return true
            }
        }

        return false
    }

    // MARK: - Private helpers

    private func findRunningApp(named appName: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        let loweredName = appName.lowercased()

        // First try matching by bundle identifier (most reliable)
        if let bundleIds = Self.appBundleIds[loweredName] {
            if let app = apps.first(where: { app in
                guard let bundleId = app.bundleIdentifier else { return false }
                return bundleIds.contains(bundleId)
            }) {
                return app
            }
        }

        // Fall back to name matching
        return apps.first { runningApp in
            let name = runningApp.localizedName?.lowercased() ?? ""
            return name.contains(loweredName) ||
                   ProcessScanner.appNameMap.values.contains(where: { $0 == loweredName && name.contains($0) })
        }
    }

    private func findAppByPid(_ pid: Int?) -> NSRunningApplication? {
        guard let pid else { return nil }

        var currentPid = pid
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: pid_t(currentPid)),
               app.activationPolicy == .regular {
                return app
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(currentPid)]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let ppid = Int(info.kp_eproc.e_ppid)
            if ppid <= 1 { break }
            currentPid = ppid
        }
        return nil
    }

    /// Find a terminal window whose title contains the cwd (or its last path component)
    private func findTerminalWindowByCwd(_ cwd: String) -> (NSRunningApplication, AXUIElement)? {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let terminalApps = runningTerminalApps()

        for app in terminalApps {
            let appRef = AXUIElementCreateApplication(app.processIdentifier)

            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                guard let title = windowTitle(window) else { continue }

                // Match full path first, then directory name
                if title.contains(cwd) || title.contains(dirName) {
                    return (app, window)
                }
            }
        }

        return nil
    }

    /// Get all running terminal apps
    private func runningTerminalApps() -> [NSRunningApplication] {
        let apps = NSWorkspace.shared.runningApplications
        return apps.filter { app in
            guard app.activationPolicy == .regular else { return false }
            if let bundleId = app.bundleIdentifier,
               Self.terminalBundleIds.contains(bundleId) {
                return true
            }
            // Also match by name for terminals not in the bundle ID list
            let name = (app.localizedName ?? "").lowercased()
            return ProcessScanner.appNameMap.keys.contains(where: { $0.lowercased() == name })
        }
    }

    /// Get the title of an AXUIElement window
    private func windowTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else { return nil }
        return title
    }

    /// Find any running terminal app as a last resort
    private func findAnyTerminalApp() -> NSRunningApplication? {
        return runningTerminalApps().first
    }

    /// Raise a window in the app whose title matches the cwd
    private func raiseWindowByCwd(_ cwd: String, in app: NSRunningApplication) {
        let dirName = URL(fileURLWithPath: cwd).lastPathComponent
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        for window in windows {
            guard let title = windowTitle(window) else { continue }
            if title.contains(cwd) || title.contains(dirName) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }

    private func raiseWindowForPid(_ pid: Int, in app: NSRunningApplication) {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        if let window = windows.first {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
        }
    }
}
#endif
