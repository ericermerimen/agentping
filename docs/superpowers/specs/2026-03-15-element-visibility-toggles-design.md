# Element Visibility Toggles

**Date:** 2026-03-15
**Status:** Draft
**Version:** 0.8.0
**Depends on:** v0.7.0 (Adaptive Density + Dot Grid, DisplayPreferences)

## Problem

After v0.7 introduces adaptive density (expanded vs compact rows), power users still have different preferences for how much detail they want in expanded rows. Some want the full kitchen-sink view. Others want to strip away elements they never look at -- the app badge, the subtitle, the context bar -- to reduce visual noise without going all the way down to compact rows.

There is no way to customize this today. Every expanded row shows every element.

## Solution

Add element visibility toggles in Preferences > General > Display. Each toggle controls whether a specific UI element appears in `ExpandedRowView`. All toggles default to ON (preserving current behavior). Users can progressively strip away elements to find their preferred density.

This only affects `ExpandedRowView`. `CompactRowView` already hides everything by design. `SessionHoverView` always shows full detail regardless of toggles -- it is the escape hatch for "I hid this but sometimes need to see it."

## Toggles

| Toggle | @AppStorage key | Default | What it controls |
|--------|----------------|---------|-----------------|
| Show app badge | `showAppBadge` | `true` | The app name pill (e.g. "Cursor", "VSCode") in the expanded row header |
| Show task/subtitle | `showSubtitle` | `true` | The task description or path line below the project name |
| Show context bar | `showContextBar` | `true` | The context window progress bar and percentage |
| Show idle duration | `showIdleDuration` | `true` | When OFF, idle sessions show "Idle" instead of "idle 5m" / "idle 2h" |
| Show project grouping | `showProjectGrouping` | `true` | When OFF, project group headers are hidden; sessions still sort by project internally |

### Toggle Behaviors

**Show app badge (OFF):** The app name pill next to the project name disappears. The project name and pin icon remain. This is the lightest toggle -- removes a small visual element.

**Show task/subtitle (OFF):** The second line (task description or path) disappears. Rows become shorter. The project name is still visible, and the full task is always available in the hover popover.

**Show context bar (OFF):** The context window progress bar and percentage disappear. Context warnings still fire via notifications. Context info is still in the hover popover. Cost display (if enabled) is unaffected.

**Show idle duration (OFF):** Idle (non-fresh) sessions display "Idle" instead of "idle 5m", "idle 2h", etc. Fresh idle sessions still show "Ready". Running sessions still show "Running". This only affects the elapsed time suffix. Rationale: some users don't care how long a session has been idle, only that it is idle.

**Show project grouping (OFF):** The uppercase project group headers (e.g. "PE-UI  3") disappear from the active session list. Sessions maintain their existing sort order (pinned first, then status priority). The grouping logic still runs internally -- it just doesn't render headers. When there is only one project, headers are already hidden (existing behavior), so this toggle only has a visible effect with multiple projects.

## Architecture

### DisplayPreferences

All toggles live in the `DisplayPreferences` ObservableObject created in v0.7. No new files needed.

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

### Data Flow

```
DisplayPreferences (@EnvironmentObject)
    │
    ├── PreferencesView (GeneralTab) -- Toggle bindings
    │
    ├── PopoverView -- reads showProjectGrouping
    │   └── activeSessionList -- conditionally renders project headers
    │
    └── ExpandedRowView -- reads showAppBadge, showSubtitle, showContextBar, showIdleDuration
        (passed as individual Bools, not the whole object)
```

`ExpandedRowView` receives display toggles as individual `Bool` parameters rather than the full `DisplayPreferences` object. This keeps the view testable and previewable without needing an environment object, consistent with how `costTrackingEnabled` is already passed.

### What Is NOT Affected

- **CompactRowView** -- already minimal, no toggles apply
- **DotGridView / DotCellView** -- dot grid is inherently minimal, no toggles apply
- **SessionHoverView** -- always shows full detail (task, context, cost, path, model)
- **Session model** -- no data model changes
- **API** -- no API changes
- **Notifications** -- context window warnings still fire regardless of `showContextBar`

## Preferences UI

New "Display" section in Preferences > General tab, placed after the existing "Monitoring" section:

```
Section("Display") {
    Toggle("Show app badge", isOn: $displayPrefs.showAppBadge)
    Toggle("Show task/subtitle", isOn: $displayPrefs.showSubtitle)
    Toggle("Show context bar", isOn: $displayPrefs.showContextBar)
    Toggle("Show idle duration", isOn: $displayPrefs.showIdleDuration)
    Toggle("Show project grouping headers", isOn: $displayPrefs.showProjectGrouping)
}
```

All toggles use default SwiftUI `Toggle` controls. No explanatory text needed -- the labels are self-descriptive. Changes apply immediately (no save/apply button) since `@AppStorage` is reactive.

## Files Changed

| File | Change |
|------|--------|
| `Sources/AgentPing/DisplayPreferences.swift` | Add 5 `@AppStorage` properties |
| `Sources/AgentPing/Views/PreferencesView.swift` | Add "Display" section with 5 toggles in GeneralTab |
| `Sources/AgentPing/Views/ExpandedRowView.swift` | Accept display booleans, conditionally render elements |
| `Sources/AgentPing/Views/PopoverView.swift` | Pass display prefs to ExpandedRowView, conditionally render project headers |

### Not Changed

- `CompactRowView.swift` -- no toggles apply
- `DotGridView.swift` -- no toggles apply
- `SessionHoverView.swift` -- always shows full detail
- `Session.swift` -- no model changes
- `AgentPingApp.swift` -- DisplayPreferences already injected in v0.7

## Edge Cases

- **All toggles OFF:** ExpandedRowView shows only: project name + pin icon on the left, status label on the right, accent bar, background tint. This is a middle ground between expanded and compact -- more detail than CompactRowView (accent bar, background tint, cost) but less than the full expanded row.
- **Toggle changed while popover is open:** Changes apply immediately via `@AppStorage` reactivity. No restart needed.
- **Dot grid mode:** Toggles have no visible effect in dot grid mode. They only apply when the list view is showing expanded rows.
- **Debug info:** Add toggle states to "Copy Debug Info" for support diagnostics.

## Rollout

- All toggles default to ON -- zero change in default appearance
- No migration needed
- Users discover toggles naturally in Preferences > General > Display
- Revert: `git revert` or ship next version removing the toggles
