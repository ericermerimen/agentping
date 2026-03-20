# Implement Adaptive Density (v0.7.0)

Read CLAUDE.md first for full project context.

## What you're building

**Adaptive Density** in list view -- sessions that need attention (needsInput, error, freshIdle) get expanded rows with full detail. Sessions that are just working (running, idle, done) get compact single-line rows showing only project name + status.

## Implementation steps (execute in order)

### Step 1: Foundation

**Create `Sources/AgentPing/DisplayPreferences.swift`:**

```swift
import SwiftUI

class DisplayPreferences: ObservableObject {
    @AppStorage("costTrackingEnabled") var costTrackingEnabled = false
}
```

**Edit `Sources/AgentPingCore/Models/Session.swift`** -- add these extensions at the bottom (after the existing code). These extract shared display logic from SessionRowView so all views can reuse it:

```swift
import Foundation

extension Session {
    public var isAttention: Bool {
        status == .needsInput || status == .error || isFreshIdle
    }

    public var isHomeCwd: Bool {
        guard let cwd = cwd else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd == home || cwd == home + "/"
    }

    public var projectName: String {
        if let cwd = cwd, !cwd.isEmpty, !isHomeCwd {
            let last = URL(fileURLWithPath: cwd).lastPathComponent
            if !last.isEmpty { return last }
        }
        if let task = taskDescription, !task.isEmpty {
            return task
        }
        return name ?? "Unnamed"
    }

    public var displayPath: String {
        guard let cwd = cwd, !cwd.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    public var subtitle: String? {
        if isHomeCwd { return "~" }
        if let task = taskDescription, !task.isEmpty, !isHomeCwd {
            return task
        }
        return displayPath.isEmpty ? nil : displayPath
    }

    public func idleElapsed(now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(lastEventAt)))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "idle \(h)h" }
        if m > 0 { return "idle \(m)m" }
        return "idle"
    }
}
```

Run `swift build` to verify.

### Step 2: Rename SessionRowView to ExpandedRowView

1. `git mv Sources/AgentPing/Views/SessionRowView.swift Sources/AgentPing/Views/ExpandedRowView.swift`
2. In the renamed file, rename the struct from `SessionRowView` to `ExpandedRowView`
3. Replace the private computed properties `isHomeCwd`, `projectName`, `subtitle`, `displayPath` with `session.isHomeCwd`, `session.projectName`, `session.subtitle`, `session.displayPath` (the Session extensions from Step 1)
4. Replace `private var isAttention: Bool` with `session.isAttention`
5. Remove `@AppStorage("costTrackingEnabled")` -- instead accept `costTrackingEnabled: Bool` as an init parameter (passed from parent)
6. In `PopoverView.swift`, update the reference from `SessionRowView` to `ExpandedRowView`, pass `costTrackingEnabled` from the view's `@AppStorage`

Run `swift build` to verify. App should look identical.

### Step 3: Create CompactRowView

**Create `Sources/AgentPing/Views/CompactRowView.swift`:**

A minimal single-line session row for "working" sessions (running, idle, done):
- HStack: project name (left, size 12, secondary) + status label (right, size 11, colored)
- Padding: horizontal 14, vertical 6
- Hover background: `Color.primary.opacity(isHovered ? 0.04 : 0)`
- Same hover popover pattern as ExpandedRowView: show `SessionHoverView` after 0.4s delay
- Same click behavior: `onTap` closure
- Same `onReviewed` closure (for freshIdle sessions that might transition)
- Use `session.projectName` from Session extension
- Status label logic: Running=green, idle Xm=tertiary, Done=tertiary
- Accessibility label: "\(projectName), \(status)"
- No accent bar, no app badge, no subtitle line, no context bar, no cost display

Keep it simple -- around 80 lines.

Run `swift build` to verify.

### Step 4: Adaptive Density in PopoverView

1. In `AgentPingApp.swift` (`AppDelegate`), create a stored property for `DisplayPreferences`:
   ```swift
   let displayPreferences = DisplayPreferences()
   ```
   Inject it into the PopoverView via `.environmentObject(displayPreferences)`.

2. In `PopoverView.swift`:
   - Add `@EnvironmentObject var displayPrefs: DisplayPreferences`
   - In `sessionRow()`, switch between ExpandedRowView and CompactRowView based on `session.isAttention`:
     ```swift
     if session.isAttention {
         ExpandedRowView(session: session, costTrackingEnabled: displayPrefs.costTrackingEnabled, onTap: {...}, onReviewed: {...})
     } else {
         CompactRowView(session: session, onTap: {...}, onReviewed: {...})
     }
     ```
   - Replace the local `@AppStorage("costTrackingEnabled")` with `displayPrefs.costTrackingEnabled`
   - History tab: use `CompactRowView` for all sessions (they're all done/idle)
   - The existing sort order already puts attention sessions first (needsInput=0, error=1, freshIdle=2, running=3, idle=4, done=5)

Run `swift build` and test manually. Active sessions that need attention should show expanded rows, working sessions should show compact rows.

## Critical details

- The popover is 340x460 fixed size -- don't change this
- Use the exact same SF Symbol colors the app already uses: `Color(.systemGreen)`, `Color(.systemTeal)`, `Color(.systemOrange)`, `Color(.systemRed)` -- not custom hex values
- The app uses `@AppStorage` for all preferences -- keep using UserDefaults, not a custom persistence layer
- SessionHoverView is reused as-is -- do NOT modify it
- The session sort order is: pinned first, then needsInput(0) > error(1) > freshIdle(2) > running(3) > idle(4) > done(5) > unavailable(6)
- The hover popover pattern is: `@State isHovered`, `@State showHover`, `@State hoverTask: DispatchWorkItem?`, 0.4s delay, cancelled on tap and on unhover. Reuse this exact pattern in CompactRowView.
- `session.isFreshIdle` is the existing property for "idle but not yet reviewed"
- Clicking a freshIdle session calls `onReviewed?()` before `onTap?()` -- maintain this in all views

## Verification

After completing all steps:
1. `swift build -c release` must succeed with no errors
2. `swift build` for debug must succeed
3. Test manually: run the app, verify adaptive density works
4. Create a single git commit with message: `feat: add adaptive density`
