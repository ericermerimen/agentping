# Dot Grid as Menu Bar Tooltip

**Date:** 2026-03-15
**Status:** Draft
**Version:** 0.9.0
**Depends on:** v0.7.0 (DotGridView, DotCellView, dot color/pulse system)

## Problem

To check on agents, you have to click the menu bar icon to open the full popover. For the most common question -- "is anything on fire?" -- this is one interaction too many. Power users with 5+ agents running want a zero-click glance.

The dot grid from v0.7 already encodes session status as color and animation. Surfacing it on hover over the menu bar icon turns AgentPing into a true ambient monitor: hover to glance, click only when something needs attention.

## Solution

A small, non-interactive tooltip-style popover appears when the cursor hovers over the AgentPing menu bar icon. It shows a compact dot grid (colored circles only, no labels, no tabs, no search). Clicking the icon still opens the full popover exactly as it does today.

### Behavior Summary

| Trigger | Action |
|---------|--------|
| Hover over menu bar icon (0.3s delay) | Show mini dot grid popover |
| Cursor leaves status item area | Dismiss mini popover |
| Click menu bar icon | Dismiss mini popover (if shown), open full popover |
| Global hotkey (Ctrl+Option+A) | No change -- toggles full popover only |
| Full popover already open | Do not show mini popover on hover |
| 0 active sessions | Do not show mini popover on hover |

### What the Mini Popover Shows

- Colored dots only. No labels, no project names, no tabs, no search, no footer.
- Same dot colors as DotGridView: green (running), teal (ready), orange (needs input), red (error), gray (idle), dark gray (done).
- Same pulse animations as DotGridView: 2s slow pulse (running), 1.5s medium pulse (needs input), 1s fast pulse (error).
- Same glow radii as DotCellView.
- Dots are non-interactive: no click, no hover popover on individual dots, no context menu.
- Same sort order as the full dot grid: pinned first, then status priority (needsInput > error > freshIdle > running > idle > done).

### Layout

Mini popover size: approximately 160x120 points (adjusts slightly based on dot count).

3-column grid layout. Dot size: 16pt diameter (vs 28pt in the full DotGridView). Spacing: 10pt between dots.

```
  +---------------------------+
  |    (o)    (o)    (o)      |
  |                           |
  |    (o)    (o)    (o)      |
  |                           |
  |    (o)    (o)             |
  +---------------------------+
```

Pulse animation overlay scales proportionally (24pt frame for the pulse circle, vs 36pt in the full grid).

### Edge Cases

- **0 active sessions:** Mini popover does not appear. Hover is a no-op.
- **1 session:** Single dot, centered in a ~80x60 popover.
- **2-3 sessions:** Single row, 3-column grid, shorter popover height.
- **4-6 sessions:** Two rows.
- **7-9 sessions:** Three rows.
- **10+ sessions:** Grid continues to grow. The popover height adjusts up to a max of ~200pt, after which it clips (unlikely scenario -- users rarely have 10+ active sessions in the dot grid view).
- **Full popover is open:** `miniPopover` is not shown. The hover tracking still fires but the handler early-returns when `popover.isShown` is true.
- **Rapid hover in/out:** The 0.3s delay prevents flicker. If the cursor leaves before 0.3s, the pending show is cancelled.
- **Click during hover delay:** The pending show is cancelled and the full popover opens immediately.
- **Menu bar icon position:** The mini popover anchors to `statusItem.button` with `.minY` edge, same as the full popover. It appears directly below the icon.

## Technical Design

### NSTrackingArea on Status Bar Button

The status bar button (`statusItem.button`) gets an `NSTrackingArea` configured for `mouseEnteredAndExited` + `activeAlways`. This detects when the cursor enters/exits the menu bar icon area.

```swift
// In AppDelegate, after statusItem is created:
if let button = statusItem.button {
    let trackingArea = NSTrackingArea(
        rect: button.bounds,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil
    )
    button.addTrackingArea(trackingArea)
}
```

The `AppDelegate` overrides `mouseEntered(with:)` and `mouseExited(with:)` to handle hover detection. Because `AppDelegate` is an `NSObject` but not an `NSView`/`NSResponder`, it cannot directly receive tracking area events. Instead, a lightweight `StatusBarButtonMonitor` subclass of `NSView` is overlaid on the button, or the tracking area owner is set to a helper `NSResponder`.

Simpler approach: use a custom `NSButton` subclass for the status item button or overlay a transparent `NSView` that owns the tracking area. However, `NSStatusItem.button` is system-provided and cannot be replaced with a subclass.

**Chosen approach:** Install a local `NSEvent` monitor for `mouseEntered`/`mouseExited` events targeting the status item button's tracking area. Alternatively, use a polling-based approach with `NSEvent.addLocalMonitorForEvents(matching: .mouseMoved)` to detect when the cursor is inside the button's screen rect. Both work, but the tracking area approach is cleaner.

**Actual implementation:** Create a `StatusItemHoverMonitor` helper class that:
1. Takes the `statusItem.button` reference
2. Adds an `NSTrackingArea` to the button
3. Installs a local event monitor for `.mouseEntered` and `.mouseExited` events
4. Calls back to `AppDelegate` via closures for `onHoverStart` and `onHoverEnd`

### Two Popovers: Mini + Full

AppDelegate manages two `NSPopover` instances:

```swift
var popover: NSPopover!       // Full popover (existing, 340x460)
var miniPopover: NSPopover!   // Mini dot grid (new, ~160x120)
```

Rules for conflict avoidance:
- Only one popover can be shown at a time.
- `togglePopover()` (click handler) dismisses `miniPopover` before showing `popover`.
- `showMiniPopover()` (hover handler) early-returns if `popover.isShown`.
- `miniPopover.behavior = .semitransient` -- it dismisses on any interaction outside it, but does not steal focus.
- `popover.behavior = .transient` -- unchanged.

### Mini Popover Content

A new `MiniDotGridView` SwiftUI view, hosted in the mini popover's `NSHostingController`:

```swift
struct MiniDotGridView: View {
    let sessions: [Session]

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

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

`MiniDotView` is a stripped-down version of `DotCellView`:
- 16pt diameter main circle (no label below)
- Same `dotColor` logic (reuses `Session` color helpers or duplicates the switch -- both are trivial)
- Same pulse animation (scaled down: 24pt pulse overlay, same timing)
- Same glow shadow (scaled radius: roughly 60% of full DotCellView values)
- No hover popover, no `onTapGesture`, no context menu
- No accessibility interaction (the mini popover is transient and non-interactive)

### Hover Delay and Click Disambiguation

```swift
private var hoverTimer: DispatchWorkItem?

// Called by tracking area / event monitor
func statusItemMouseEntered() {
    guard !popover.isShown else { return }
    guard !manager.activeSessions.isEmpty else { return }

    hoverTimer?.cancel()
    let task = DispatchWorkItem { [weak self] in
        self?.showMiniPopover()
    }
    hoverTimer = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
}

func statusItemMouseExited() {
    hoverTimer?.cancel()
    hoverTimer = nil
    miniPopover.performClose(nil)
}

@objc func togglePopover() {
    // Cancel any pending hover
    hoverTimer?.cancel()
    hoverTimer = nil

    // Dismiss mini popover if shown
    if miniPopover.isShown {
        miniPopover.performClose(nil)
    }

    // Toggle full popover (existing logic)
    if popover.isShown {
        popover.performClose(nil)
    } else if let button = statusItem.button {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}
```

The 0.3s delay ensures:
- Quick mouse passes over the icon area don't trigger the mini popover (prevents flicker).
- A click arrives before the 0.3s delay fires, so the mini popover never appears on click.
- If the user hovers and then clicks (after mini popover is visible), `togglePopover()` closes the mini and opens the full popover seamlessly.

### Thread Safety

All hover events arrive on the main thread (NSEvent monitors and NSTrackingArea callbacks are main-thread). The `hoverTimer` uses `DispatchQueue.main.asyncAfter`, which is also main-thread. No thread safety concerns.

`SessionManager.activeSessions` is read on the main thread in the hover handler. This is the same pattern used by `updateIcon(sessions:)` and other existing code.

### Mini Popover Sizing

The mini popover's `contentSize` is calculated based on session count:

```swift
private func miniPopoverSize(sessionCount: Int) -> NSSize {
    let cols = 3
    let dotSize: CGFloat = 16
    let spacing: CGFloat = 10
    let padding: CGFloat = 12

    let rows = max(1, Int(ceil(Double(sessionCount) / Double(cols))))
    let width = (dotSize * CGFloat(cols)) + (spacing * CGFloat(cols - 1)) + (padding * 2)
    let height = (dotSize * CGFloat(rows)) + (spacing * CGFloat(max(0, rows - 1))) + (padding * 2)

    return NSSize(width: max(80, width), height: max(50, min(200, height)))
}
```

This keeps the popover tight around the dots rather than using a fixed size.

### Updating the Mini Popover Content

When the mini popover is visible and sessions change (new session, status change), the content should update. Since the mini popover hosts a SwiftUI view that observes `SessionManager`, it updates reactively via `@ObservedObject` -- same pattern as the full popover.

```swift
// Mini popover setup (in applicationDidFinishLaunching or lazily)
miniPopover = NSPopover()
miniPopover.behavior = .semitransient
miniPopover.animates = true
miniPopover.contentViewController = NSHostingController(
    rootView: MiniDotGridView(manager: manager)
)
```

`MiniDotGridView` takes `@ObservedObject var manager: SessionManager` and reads `manager.activeSessions` directly, applying the same sort as the full dot grid.

### Global Hotkey Interaction

The global hotkey (Ctrl+Option+A) calls `togglePopover()`, which already cancels the hover timer and dismisses the mini popover. No additional handling needed.

## Files Changed

| File | Change |
|------|--------|
| `Views/MiniDotGridView.swift` | **New** -- MiniDotGridView + MiniDotView (non-interactive mini dots) |
| `AgentPingApp.swift` | Add `miniPopover`, hover tracking setup, `showMiniPopover()`, update `togglePopover()` |
| `StatusItemHoverMonitor.swift` | **New** -- NSTrackingArea helper for status item hover detection |

### Not Changed

- `DotGridView.swift` -- the full interactive grid is unchanged
- `PopoverView.swift` -- the full popover is unchanged
- `Session.swift` -- no model changes
- `SessionManager.swift` -- no logic changes
- `APIRouter.swift` / `APIServer.swift` -- no API changes
- `PreferencesView.swift` -- no settings for this feature (could add a toggle in a future version)

## Future Considerations

- **Preferences toggle:** "Show dot grid on hover" in General tab. Not needed for v0.9 -- the feature is lightweight and unobtrusive. If users complain, add the toggle.
- **Click-through on mini dots:** In a future version, clicking a dot in the mini popover could jump to that session's window directly without opening the full popover. This would require making the mini popover interactive, which adds complexity (distinguishing click-on-dot vs click-to-open-full-popover).
- **Badge overlay on dots:** Show a tiny number or icon overlay on dots that need input, so color-blind users get a secondary signal. This would apply to both the mini and full dot grids.
- **Dark/light mode:** Dot colors use system colors (`Color(.systemGreen)` etc.) which adapt automatically. The mini popover background uses the default `NSPopover` appearance, which also adapts.
