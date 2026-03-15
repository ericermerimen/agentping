# Implementation Plan: Dot Grid as Menu Bar Tooltip

**Spec:** `docs/superpowers/specs/2026-03-15-menu-bar-dot-grid-design.md`
**Target version:** 0.9.0

## Dependency Graph

```
  Step 1: StatusItemHoverMonitor (tracking area helper)
     |
     +---> Step 2: MiniDotGridView + MiniDotView (SwiftUI views)
              |
              +---> Step 3: Wire into AppDelegate (mini popover, hover logic, click disambiguation)
                       |
                       +---> Step 4: Dynamic sizing + edge cases + polish
```

All steps are sequential. Each builds on the previous.

## Steps

### Step 1: StatusItemHoverMonitor

**Files:**
- Create `Sources/AgentPing/StatusItemHoverMonitor.swift`

**Tasks:**

1. Create a `StatusItemHoverMonitor` class that manages hover detection for the status bar button. The challenge is that `NSStatusItem.button` is a system-provided `NSButton` -- we cannot subclass it, but we can add tracking areas to it and install event monitors.

2. Implementation approach -- install an `NSTrackingArea` on the status item button and use a local event monitor to capture the enter/exit events:

   ```swift
   final class StatusItemHoverMonitor {
       private weak var button: NSStatusBarButton?
       private var trackingArea: NSTrackingArea?
       private var eventMonitor: Any?
       var onMouseEntered: (() -> Void)?
       var onMouseExited: (() -> Void)?

       init(button: NSStatusBarButton) { ... }
       func install() { ... }
       func uninstall() { ... }
   }
   ```

3. The `NSTrackingArea` is configured with `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]`. The `owner` must be an `NSResponder` that can receive `mouseEntered(with:)`/`mouseExited(with:)` calls. Since we cannot make `StatusItemHoverMonitor` own these (it is not an NSResponder), use a small inner `NSView` overlay that is added as a subview of the button, or use an `NSEvent.addLocalMonitorForEvents(matching:)` approach instead.

4. **Preferred approach: local event monitor.** Simpler and avoids subview hacks on the system button.
   - Use `NSEvent.addLocalMonitorForEvents(matching: .mouseMoved)` to check if the cursor is inside the button's screen-space rect.
   - Track enter/exit state manually with a `private var isInside = false` flag.
   - Call `onMouseEntered`/`onMouseExited` on transitions.
   - This approach handles `inVisibleRect` automatically and works even when the menu bar layout changes (e.g., notch avoidance on MacBooks).

   ```swift
   func install() {
       eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
           self?.checkHover()
           return event
       }
   }

   private func checkHover() {
       guard let button = button,
             let window = button.window else { return }
       let mouseLocation = NSEvent.mouseLocation
       let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
       let nowInside = buttonRect.contains(mouseLocation)

       if nowInside && !isInside {
           isInside = true
           onMouseEntered?()
       } else if !nowInside && isInside {
           isInside = false
           onMouseExited?()
       }
   }
   ```

5. **Caveat with local event monitor:** `addLocalMonitorForEvents` only fires for events delivered to the app's own windows. When the cursor is over the menu bar and the app is not key, the events may not fire. Alternative: use `addGlobalMonitorForEvents(matching: .mouseMoved)` for events outside the app's windows. Combine both local and global monitors to cover all cases.

   ```swift
   func install() {
       localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
           self?.checkHover()
           return event
       }
       globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
           self?.checkHover()
       }
   }
   ```

   The global monitor is what actually matters here -- the cursor is over the menu bar (system space), not over an app window.

**Verification:** `swift build` succeeds. Write a quick test: add a `print("entered")`/`print("exited")` in the callbacks and run the app. Verify they fire when hovering over the menu bar icon. Verify no events fire when the cursor is elsewhere.

---

### Step 2: MiniDotGridView + MiniDotView

**Files:**
- Create `Sources/AgentPing/Views/MiniDotGridView.swift`

**Tasks:**

1. Create `MiniDotView` -- a non-interactive version of `DotCellView`:
   ```swift
   struct MiniDotView: View {
       let session: Session
       @State private var isPulsing = false

       var body: some View {
           ZStack {
               // Pulse overlay (same animation, scaled down)
               if let speed = pulseSpeed {
                   Circle()
                       .fill(dotColor)
                       .frame(width: 24, height: 24)
                       .scaleEffect(isPulsing ? 1.6 : 1.0)
                       .opacity(isPulsing ? 0.0 : 0.6)
                       .animation(
                           .easeOut(duration: speed).repeatForever(autoreverses: false),
                           value: isPulsing
                       )
                       .onAppear { isPulsing = true }
               }

               // Main dot
               Circle()
                   .fill(dotColor)
                   .frame(width: 16, height: 16)
                   .shadow(color: dotColor.opacity(0.4), radius: glowRadius)
           }
           .frame(width: 24, height: 24)
       }
   }
   ```

2. Dot color, glow radius, and pulse speed logic is duplicated from `DotCellView`. The values are identical except for sizing:
   - `dotColor`: same switch statement (reuse or duplicate -- it is 10 lines, duplication is clearer than abstraction here)
   - `glowRadius`: scale down -- `5` / `3` / `2` / `0` instead of `8` / `5` / `3` / `0`
   - `pulseSpeed`: identical values (`1.0` / `1.5` / `2.0`)

3. No `onTapGesture`, no `onHover`, no `.popover`, no `.contextMenu`, no label. Pure visual.

4. Create `MiniDotGridView`:
   ```swift
   struct MiniDotGridView: View {
       @ObservedObject var manager: SessionManager

       private let columns = Array(repeating: GridItem(.flexible()), count: 3)

       private var sessions: [Session] {
           manager.activeSessions.sorted { a, b in
               if a.pinned != b.pinned { return a.pinned }
               return sortPriority(a) < sortPriority(b)
           }
       }

       var body: some View {
           LazyVGrid(columns: columns, spacing: 10) {
               ForEach(sessions) { session in
                   MiniDotView(session: session)
               }
           }
           .padding(12)
       }
   }
   ```

5. The `sortPriority` helper reuses the same logic from `PopoverView` (freshIdle = 2, otherwise `session.status.sortPriority`). Duplicate the 3-line helper rather than extracting to a shared location -- it is not worth the abstraction.

6. No empty state in `MiniDotGridView`. The caller (AppDelegate) checks for 0 sessions before showing the mini popover.

**Verification:** `swift build` succeeds. Add a `#Preview` with mock sessions at various statuses to visually verify dot sizes, colors, glow, and pulse animations.

---

### Step 3: Wire into AppDelegate

**Files:**
- Edit `Sources/AgentPing/AgentPingApp.swift`

**Tasks:**

1. Add new properties:
   ```swift
   var miniPopover: NSPopover!
   var hoverMonitor: StatusItemHoverMonitor?
   var hoverTimer: DispatchWorkItem?
   ```

2. In `applicationDidFinishLaunching`, after the full popover is created, set up the mini popover:
   ```swift
   miniPopover = NSPopover()
   miniPopover.behavior = .semitransient
   miniPopover.animates = true
   miniPopover.contentViewController = NSHostingController(
       rootView: MiniDotGridView(manager: manager)
   )
   ```

   Note: `.semitransient` means the popover will auto-dismiss if the user clicks elsewhere or interacts with another app, but it will not dismiss just because the app loses focus. This is the right behavior for a tooltip-like preview.

3. Set up hover monitoring after the status item is created:
   ```swift
   if let button = statusItem.button {
       hoverMonitor = StatusItemHoverMonitor(button: button)
       hoverMonitor?.onMouseEntered = { [weak self] in
           self?.statusItemMouseEntered()
       }
       hoverMonitor?.onMouseExited = { [weak self] in
           self?.statusItemMouseExited()
       }
       hoverMonitor?.install()
   }
   ```

4. Add hover handlers:
   ```swift
   private func statusItemMouseEntered() {
       // Don't show mini popover if full popover is already open
       guard !popover.isShown else { return }
       // Don't show if no active sessions
       guard !manager.activeSessions.isEmpty else { return }

       hoverTimer?.cancel()
       let task = DispatchWorkItem { [weak self] in
           self?.showMiniPopover()
       }
       hoverTimer = task
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
   }

   private func statusItemMouseExited() {
       hoverTimer?.cancel()
       hoverTimer = nil
       if miniPopover.isShown {
           miniPopover.performClose(nil)
       }
   }

   private func showMiniPopover() {
       guard !popover.isShown else { return }
       guard !miniPopover.isShown else { return }
       guard !manager.activeSessions.isEmpty else { return }

       // Update content size based on session count
       miniPopover.contentSize = miniPopoverSize(
           sessionCount: manager.activeSessions.count
       )

       if let button = statusItem.button {
           miniPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
       }
   }
   ```

5. Update `togglePopover()` to handle click disambiguation:
   ```swift
   @objc func togglePopover() {
       // Cancel any pending hover show
       hoverTimer?.cancel()
       hoverTimer = nil

       // Dismiss mini popover if shown
       if miniPopover.isShown {
           miniPopover.performClose(nil)
       }

       // Existing full popover toggle logic
       if popover.isShown {
           popover.performClose(nil)
       } else if let button = statusItem.button {
           popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
       }
   }
   ```

6. Add the sizing helper:
   ```swift
   private func miniPopoverSize(sessionCount: Int) -> NSSize {
       let cols = 3
       let cellSize: CGFloat = 24  // frame size of each MiniDotView
       let spacing: CGFloat = 10
       let padding: CGFloat = 12

       let rows = max(1, Int(ceil(Double(sessionCount) / Double(cols))))
       let width = (cellSize * CGFloat(cols))
                   + (spacing * CGFloat(cols - 1))
                   + (padding * 2)
       let height = (cellSize * CGFloat(rows))
                    + (spacing * CGFloat(max(0, rows - 1)))
                    + (padding * 2)

       return NSSize(
           width: max(80, width),
           height: max(50, min(200, height))
       )
   }
   ```

**Verification:** Build and run the app. Hover over the menu bar icon -- after 0.3s the mini popover should appear showing colored dots. Move cursor away -- mini popover dismisses. Click the icon -- mini popover dismisses (if shown) and full popover opens. Open full popover, then hover over icon -- mini popover should NOT appear.

---

### Step 4: Dynamic Sizing + Edge Cases + Polish

**Files:**
- Edit `Sources/AgentPing/AgentPingApp.swift` (minor tweaks)
- Edit `Sources/AgentPing/Views/MiniDotGridView.swift` (minor tweaks)

**Tasks:**

1. **Re-entrancy guard.** If `showMiniPopover()` fires at the exact moment the user clicks (race between 0.3s timer and click), we could momentarily flash the mini popover. The `togglePopover()` cancellation handles this, but add a defensive check:
   ```swift
   private func showMiniPopover() {
       guard hoverTimer != nil else { return }  // was cancelled by click
       // ... rest of method
   }
   ```
   Actually, `DispatchWorkItem` cancellation means the block won't execute if cancelled. But `asyncAfter` may have already captured the work item. Safest: check `hoverTimer?.isCancelled != true` inside the block itself, or simply rely on the `guard !popover.isShown` check which covers the click case (full popover will be shown or in the process of showing).

2. **Full popover close -> hover re-enable.** When the full popover is closed (click on icon, or click outside), the user's cursor may still be over the menu bar icon. The hover monitor will not re-fire `mouseEntered` because the cursor never left. This means the mini popover won't appear after closing the full popover until the cursor leaves and re-enters.

   This is actually the desired behavior -- closing the full popover should not immediately show the mini popover. The user just finished interacting with the full UI; showing a tooltip would be jarring.

3. **Mini popover content reactivity.** Verify that the `MiniDotGridView` updates when sessions change while the mini popover is visible. Since it uses `@ObservedObject var manager: SessionManager`, SwiftUI should re-render when `manager.sessions` changes. Test by:
   - Showing the mini popover (hover over icon)
   - Triggering a session status change (e.g., `agentping report --session test --event stop`)
   - Verifying the dot color updates in the mini popover

4. **Cleanup on app termination.** In `applicationWillTerminate` (or `deinit`), call `hoverMonitor?.uninstall()` to remove the global event monitor. Leaking global monitors can cause issues.

5. **Accessibility.** The mini popover is transient and non-interactive, so it does not need VoiceOver support. The full popover and dot grid remain accessible. Add `accessibilityHidden(true)` to `MiniDotGridView` to prevent VoiceOver from reading it.

6. **Visual polish.** Test the following scenarios and adjust:
   - 1 session: the popover should not look awkwardly empty. Verify the min size (80x50) looks reasonable with a single centered dot.
   - 9 sessions: 3x3 grid. Verify spacing and alignment.
   - Pulse animations at 16pt dot size -- verify they are visible but not overwhelming. If too subtle, increase the pulse overlay to 28pt. If too loud, reduce to 20pt.
   - Dark mode and light mode -- verify dot colors are legible in both.

7. **Performance.** The global `mouseMoved` event monitor fires on every mouse movement across the entire screen. The `checkHover()` method is lightweight (one rect-contains check), but verify there is no measurable CPU impact. If there is, throttle with a simple `Date` comparison (skip if < 50ms since last check).

**Verification:** Full manual QA:
- Hover in/out rapidly (no flicker)
- Hover, wait, see mini popover, click (full popover opens, mini dismissed)
- Open full popover via hotkey, hover over icon (no mini popover)
- Close full popover, cursor still over icon (no mini popover until re-enter)
- 0 sessions: hover is no-op
- 1 session: single dot, reasonable size
- 6 sessions: 2x3 grid
- Session status change while mini popover is visible (dots update)
- Build release binary: `swift build -c release`

## Review Checkpoints

- After Step 1: Verify hover detection works (print statements in callbacks)
- After Step 2: Verify mini dot grid renders correctly in #Preview
- After Step 3: Full integration test -- hover shows mini, click shows full, no conflicts
- After Step 4: Edge cases, polish, performance check, release build
