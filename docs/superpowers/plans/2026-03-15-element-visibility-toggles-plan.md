# Implementation Plan: Element Visibility Toggles

**Spec:** `docs/superpowers/specs/2026-03-15-element-visibility-toggles-design.md`
**Target version:** 0.8.0

## Dependency Graph

```
  Step 1: Add properties to DisplayPreferences
     │
     ├──► Step 2: Add Display section to PreferencesView
     │
     ├──► Step 3: Wire toggles into ExpandedRowView
     │
     └──► Step 4: Wire showProjectGrouping into PopoverView
             │
             └──► Step 5: Debug info + verification
```

Steps 2, 3, and 4 are independent and can run in parallel after Step 1.

## Steps

### Step 1: Add Properties to DisplayPreferences

**File:** `Sources/AgentPing/DisplayPreferences.swift`

Add the 5 `@AppStorage` properties after the existing ones:

```swift
class DisplayPreferences: ObservableObject {
    // v0.7
    @AppStorage("viewMode") var viewModeRaw = "list"
    @AppStorage("costTrackingEnabled") var costTrackingEnabled = false

    // v0.8 -- element visibility
    @AppStorage("showAppBadge") var showAppBadge = true
    @AppStorage("showSubtitle") var showSubtitle = true
    @AppStorage("showContextBar") var showContextBar = true
    @AppStorage("showIdleDuration") var showIdleDuration = true
    @AppStorage("showProjectGrouping") var showProjectGrouping = true

    var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .list }
        set { viewModeRaw = newValue.rawValue }
    }
}
```

**Verification:** `swift build` succeeds.

---

### Step 2: Add Display Section to PreferencesView

**File:** `Sources/AgentPing/Views/PreferencesView.swift`

`GeneralTab` needs access to `DisplayPreferences` via `@EnvironmentObject`. Add the Display section after Monitoring:

```swift
private struct GeneralTab: View {
    @EnvironmentObject var displayPrefs: DisplayPreferences
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("scanInterval") private var scanInterval = 10.0
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }

            Section("Monitoring") {
                Picker("Scan interval", selection: $scanInterval) {
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
                Toggle("Show estimated cost per session", isOn: $displayPrefs.costTrackingEnabled)
            }

            Section("Display") {
                Toggle("Show app badge", isOn: $displayPrefs.showAppBadge)
                Toggle("Show task/subtitle", isOn: $displayPrefs.showSubtitle)
                Toggle("Show context bar", isOn: $displayPrefs.showContextBar)
                Toggle("Show idle duration", isOn: $displayPrefs.showIdleDuration)
                Toggle("Show project grouping headers", isOn: $displayPrefs.showProjectGrouping)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Data") {
                Text("Finished sessions older than 24 hours are automatically removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

Key changes:
1. Add `@EnvironmentObject var displayPrefs: DisplayPreferences`
2. Remove `@AppStorage("costTrackingEnabled")` -- use `displayPrefs.costTrackingEnabled` instead (it's already there from v0.7)
3. Add the `Section("Display")` block with 5 toggles
4. Move "Display" section between "Monitoring" and "Notifications" for logical grouping

**Note:** `PreferencesView` must have `DisplayPreferences` injected via `.environmentObject()`. Check that `AgentPingApp.swift` already does this (should be done in v0.7). If the preferences window is opened via a separate `NSWindow`, ensure it gets the environment object too.

**Verification:** Build and open Preferences. Five new toggles visible under Display. All default to ON. Toggling them persists across app restart.

---

### Step 3: Wire Toggles into ExpandedRowView

**File:** `Sources/AgentPing/Views/ExpandedRowView.swift`

Add 4 boolean parameters (not `showProjectGrouping` -- that's handled in PopoverView):

```swift
struct ExpandedRowView: View {
    let session: Session
    let costTrackingEnabled: Bool
    let showAppBadge: Bool
    let showSubtitle: Bool
    let showContextBar: Bool
    let showIdleDuration: Bool
    var onTap: (() -> Void)?
    var onReviewed: (() -> Void)?
    // ... existing @State properties
```

Default values for backward compatibility with previews:

No defaults -- all call sites will pass them explicitly. There is only one call site (PopoverView.sessionRow).

**Conditional rendering changes:**

1. **App badge** -- wrap the app badge in a condition:
```swift
if showAppBadge, let app = session.app, !app.isEmpty {
    Text(app)
        .font(.system(size: 9, weight: .medium))
        // ...
}
```

2. **Subtitle** -- wrap the subtitle in a condition:
```swift
if showSubtitle, let sub = session.subtitle {
    Text(sub)
        // ...
}
```

3. **Context bar** -- wrap in a condition:
```swift
if showContextBar, let pct = session.contextPercent, pct > 0 {
    contextBar(percent: pct)
}
```

4. **Idle duration** -- modify the idle elapsed display in the status VStack:
```swift
} else if session.status == .idle {
    Text(showIdleDuration ? idleElapsed : "Idle")
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.tertiary)
}
```

The same `showIdleDuration` logic applies to the `idleElapsed` computed in CompactRowView's `statusView`. However, the spec says toggles only affect ExpandedRowView. CompactRowView stays as-is -- its idle duration is part of its minimal identity.

**Verification:** Build and run. Toggle each preference off one by one. Confirm each element disappears from expanded rows only. Hover popover still shows full detail.

---

### Step 4: Wire showProjectGrouping into PopoverView

**File:** `Sources/AgentPing/Views/PopoverView.swift`

Two changes:

**4a.** Update `sessionRow()` to pass the new booleans:

```swift
private func sessionRow(_ session: Session) -> some View {
    VStack(spacing: 0) {
        if session.isAttention {
            ExpandedRowView(
                session: session,
                costTrackingEnabled: displayPrefs.costTrackingEnabled,
                showAppBadge: displayPrefs.showAppBadge,
                showSubtitle: displayPrefs.showSubtitle,
                showContextBar: displayPrefs.showContextBar,
                showIdleDuration: displayPrefs.showIdleDuration,
                onTap: { jumpToWindow(session: session) },
                onReviewed: { manager.markReviewed(id: session.id) }
            )
        } else {
            CompactRowView(
                session: session,
                onTap: { jumpToWindow(session: session) },
                onReviewed: { manager.markReviewed(id: session.id) }
            )
        }
    }
    .contextMenu { sessionContextMenu(session: session) }
}
```

**4b.** Conditionally render project headers in `activeSessionList`:

Current logic already skips headers when there is only one project group. Add the `showProjectGrouping` check:

```swift
@ViewBuilder
private var activeSessionList: some View {
    let groups = groupedActiveSessions()

    if groups.isEmpty {
        emptyState
    } else if groups.count == 1 || !displayPrefs.showProjectGrouping {
        // Single project or grouping disabled -- no headers
        let allSessions = groups.flatMap(\.sessions)
        ForEach(allSessions) { session in
            sessionRow(session)
        }
    } else {
        ForEach(groups, id: \.project) { group in
            projectHeader(group.project, count: group.sessions.count)
            ForEach(group.sessions) { session in
                sessionRow(session)
            }
        }
    }
}
```

When `showProjectGrouping` is OFF and there are multiple groups, we flatten all sessions into a single list. The sort order is preserved because `groupedActiveSessions()` already sorts by pinned-first then status priority before grouping.

**Verification:** Build and run with multiple projects. Toggle "Show project grouping headers" off. Headers disappear, sessions remain in the same order. Toggle back on, headers reappear.

---

### Step 5: Debug Info + Verification

**File:** `Sources/AgentPing/Views/PreferencesView.swift`

Add toggle states to `copyDebugInfo()` in `AboutTab`:

```swift
private func copyDebugInfo() {
    let activeSessions = manager.sessions.filter {
        $0.status == .running || $0.status == .needsInput || $0.status == .idle
    }.count
    let scanner = ProcessScanner()
    let claudeProcesses = scanner.scan().count
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    let viewMode = UserDefaults.standard.string(forKey: "viewMode") ?? "list"
    let defaults = UserDefaults.standard
    let hiddenElements = [
        defaults.bool(forKey: "showAppBadge") ? nil : "appBadge",
        defaults.bool(forKey: "showSubtitle") ? nil : "subtitle",
        defaults.bool(forKey: "showContextBar") ? nil : "contextBar",
        defaults.bool(forKey: "showIdleDuration") ? nil : "idleDuration",
        defaults.bool(forKey: "showProjectGrouping") ? nil : "projectGrouping",
    ].compactMap { $0 }

    let info = """
AgentPing v\(UpdateChecker.currentVersion)
macOS \(osVersion)
API port: \(apiPort)
View mode: \(viewMode)
Hidden elements: \(hiddenElements.isEmpty ? "none" : hiddenElements.joined(separator: ", "))
Active sessions: \(activeSessions)
Claude processes: \(claudeProcesses)
"""
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(info, forType: .string)
}
```

Note: `@AppStorage` defaults to `false` for unset keys, but these keys default to `true`. Since `UserDefaults.bool(forKey:)` returns `false` for unregistered keys, we need to handle the first-launch case. Use `UserDefaults.standard.object(forKey:) == nil` check or register defaults. The simplest approach: treat missing key as "shown" (default ON):

```swift
let showAppBadge = defaults.object(forKey: "showAppBadge") as? Bool ?? true
```

Apply this pattern for all 5 keys in the debug info builder.

**Verification:** Full QA pass:
1. Fresh launch -- all elements visible (defaults ON)
2. Toggle each element off individually -- only that element disappears from expanded rows
3. Toggle all off -- expanded rows show only project name, pin, status, cost, accent bar, background
4. Hover popover still shows everything regardless of toggles
5. Compact rows unaffected
6. Dot grid unaffected
7. Project grouping off -- headers gone, sort order preserved
8. Idle duration off -- "Idle" instead of "idle 5m"
9. Copy Debug Info -- shows hidden elements
10. Restart app -- preferences persist
11. `swift build -c release` succeeds

## Review Checkpoints

- After Step 1: Build passes, no visual changes
- After Steps 2-4: All toggles work independently, no regressions
- After Step 5: Debug info includes toggle state, full QA passes
