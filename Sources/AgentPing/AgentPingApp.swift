import AppKit
import SwiftUI
import Carbon.HIToolbox
import AgentPingCore
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let manager = SessionManager()
    let hookDetector = HookDetector()
    let displayPreferences = DisplayPreferences()
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var preferencesWindow: NSWindow?
    var watcher: DirectoryWatcher?
    var scanTimer: Timer?
    var syncTimer: Timer?
    var cancellables = Set<AnyCancellable>()
    var hotKeyRef: EventHotKeyRef?
    var apiServer: APIServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "AgentPing")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 460)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(manager: manager, hookDetector: hookDetector, openPreferences: { [weak self] in
                self?.openPreferences()
            }, dismissPopover: { [weak self] in
                self?.popover.performClose(nil)
            }).environmentObject(displayPreferences)
        )

        // Set up directory watcher for live updates
        watcher = DirectoryWatcher { [weak self] in
            self?.manager.reload()
        }
        watcher?.start()

        // Set up notifications
        NotificationManager.shared.setup { [weak self] sessionId in
            guard let session = self?.manager.sessions.first(where: { $0.id == sessionId }) else { return }
            self?.popover.performClose(nil)
            let jumper = WindowJumper()
            if !jumper.jumpTo(session: session) {
                NSSound.beep()
            }
        }

        // Watch for sessions that transition to needs-input
        manager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateIcon(sessions: sessions)
                self?.checkForNeedsInput(sessions: sessions)
            }
            .store(in: &cancellables)

        // Initial load
        manager.reload()

        // Auto-purge old finished sessions on launch
        manager.autoPurgeOldSessions()

        // Start API server
        let port = UInt16(UserDefaults.standard.integer(forKey: "apiPort"))
        apiServer = APIServer(store: manager.store, port: port > 0 ? port : 19199)
        Task {
            do {
                try await apiServer?.start()
            } catch {
                // Server failed to start -- app continues with file-based IPC
                print("API server failed to start: \(error)")
            }
        }

        // Register global hotkey: Ctrl+Option+A
        registerGlobalHotKey()

        // Initial sync + hook check + start periodic timers
        manager.sync()
        hookDetector.check()
        startPeriodicScan()
        startPeriodicSync()

        // Auto-check for updates on launch
        if UserDefaults.standard.object(forKey: "checkForUpdatesAutomatically") == nil {
            UserDefaults.standard.set(true, forKey: "checkForUpdatesAutomatically")
        }
        if UserDefaults.standard.bool(forKey: "checkForUpdatesAutomatically") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                UpdateChecker.shared.check()
            }
        }
    }

    private func updateIcon(sessions: [Session]) {
        guard let button = statusItem.button else { return }
        let attentionCount = sessions.filter { $0.status == .needsInput || $0.status == .error || $0.isFreshIdle }.count
        let symbolName = attentionCount > 0 ? "circle.grid.2x2.fill" : "circle.grid.2x2"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentPing")
        button.title = attentionCount > 0 ? " \(attentionCount)" : ""
    }

    private var previousNeedsInputIds = Set<String>()
    private var previousErrorIds = Set<String>()
    private var previousRunningIds = Set<String>()
    private var contextWarningIds = Set<String>()
    /// Sessions that already received a "ready" notification -- skip "done" for these
    /// to avoid double-notifying when a session goes running -> idle -> done.
    private var readyNotifiedIds = Set<String>()

    private func checkForNeedsInput(sessions: [Session]) {
        let globalNotificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true

        let currentNeedsInput = Set(sessions.filter { $0.status == .needsInput }.map(\.id))
        let newNeedsInput = currentNeedsInput.subtracting(previousNeedsInputIds)

        if globalNotificationsEnabled {
            for sessionId in newNeedsInput {
                if let session = sessions.first(where: { $0.id == sessionId }) {
                    NotificationManager.shared.sendNeedsInput(session: session)
                }
            }
        }

        previousNeedsInputIds = currentNeedsInput

        // Also notify on new errors
        let currentErrors = Set(sessions.filter { $0.status == .error }.map(\.id))
        let newErrors = currentErrors.subtracting(previousErrorIds)

        if globalNotificationsEnabled {
            for sessionId in newErrors {
                if let session = sessions.first(where: { $0.id == sessionId }) {
                    NotificationManager.shared.sendError(session: session)
                }
            }
        }

        previousErrorIds = currentErrors

        // Notify when a previously running session becomes ready (fresh idle)
        let currentFreshIdle = Set(sessions.filter { $0.isFreshIdle }.map(\.id))
        let newlyReady = currentFreshIdle.intersection(previousRunningIds)

        if globalNotificationsEnabled {
            for sessionId in newlyReady {
                if let session = sessions.first(where: { $0.id == sessionId }) {
                    NotificationManager.shared.sendReady(session: session)
                    readyNotifiedIds.insert(sessionId)
                }
            }
        }

        // Also notify when a previously running session is fully done.
        // Skip sessions that already got a "ready" notification to avoid double-notifying
        // when a session transitions running -> idle -> done in quick succession.
        let currentDone = Set(sessions.filter { $0.status == .done }.map(\.id))
        let newlyDone = currentDone.intersection(previousRunningIds)

        if globalNotificationsEnabled {
            for sessionId in newlyDone {
                guard !readyNotifiedIds.contains(sessionId) else { continue }
                if let session = sessions.first(where: { $0.id == sessionId }) {
                    NotificationManager.shared.sendDone(session: session)
                }
            }
        }

        // Clean up ready-notified tracking for sessions no longer active
        readyNotifiedIds = readyNotifiedIds.intersection(
            sessions.filter { $0.status != .done && $0.status != .error }.map(\.id)
        )

        previousRunningIds = Set(sessions.filter { $0.status == .running }.map(\.id))

        // Context window warning at 80%+
        if globalNotificationsEnabled {
            for session in sessions where session.status == .running {
                if let pct = session.contextPercent, pct >= 0.80, !contextWarningIds.contains(session.id) {
                    contextWarningIds.insert(session.id)
                    NotificationManager.shared.sendContextWarning(session: session, percent: pct)
                }
            }
        }
    }

    private func startPeriodicScan() {
        let interval = UserDefaults.standard.double(forKey: "scanInterval")
        let scanInterval = interval > 0 ? interval : 10.0

        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.manager.reload()
        }
    }

    private func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.manager.sync()
            self?.hookDetector.check()
        }
    }

    private func openPreferences() {
        popover.performClose(nil)

        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.toolbarStyle = .preference
        window.contentViewController = NSHostingController(rootView: PreferencesView(manager: manager, hookDetector: hookDetector))
        window.center()
        window.isReleasedWhenClosed = false
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        apiServer?.stop()
        watcher?.stop()
        scanTimer?.invalidate()
        syncTimer?.invalidate()
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Global Hotkey (Ctrl+Option+A)

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x41_50_4E_47), id: 1) // "APNG"
        // kVK_ANSI_A = 0x00, controlKey + optionKey
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }

        // Install Carbon event handler for the hotkey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    // Find the app delegate and toggle
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.togglePopover()
                    }
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

@main
enum EntryPoint {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
