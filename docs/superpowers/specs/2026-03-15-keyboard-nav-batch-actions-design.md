# Keyboard Navigation, Multi-Select, and Batch Actions

**Date:** 2026-03-15
**Status:** Draft
**Version:** 1.0.0

## Problem

AgentPing is mouse-only. Every interaction -- jumping to a session, pinning, marking done, deleting -- requires precise clicking. For power users running 5-10 agents, this is slow. Three specific pain points:

1. **No keyboard navigation.** Users who trigger the popover via Ctrl+Option+A still need the mouse to do anything inside it. There is no way to arrow through sessions or press Enter to jump.

2. **No multi-select.** Cleaning up after a work session means right-clicking each finished session individually and selecting "Mark as Done" or "Delete" one at a time. With 8 stale sessions, that is 16-24 clicks.

3. **No batch actions.** Even if multi-select existed, there are no bulk operations. Each session mutation goes through a single-session context menu.

## Solution

Three layers that build on each other:

1. **Keyboard navigation** -- arrow keys move a visible focus ring through the session list/grid. Enter, Space, Escape, and Tab provide keyboard-driven interaction.

2. **Multi-select** -- Cmd+Click and Shift+Click select multiple sessions in list view. Selection is visually distinct from focus.

3. **Batch actions** -- when 2+ sessions are selected, a batch action bar appears with Mark Done, Delete, and Deselect buttons.

## Architecture

### State Model

Two new `@State` properties in `PopoverView`:

```swift
@State private var focusedId: String?      // keyboard navigation
@State private var selectedIds: Set<String> // multi-select
```

Focus and selection are independent concepts:
- **Focus** = where the keyboard cursor is. One session at a time. Visible as a focus ring.
- **Selection** = which sessions are marked for batch action. Zero or many. Visible as background highlight.

Focus exists in both list and dot grid views. Selection only exists in list view.

### Keyboard Event Capture

SwiftUI inside `NSPopover` does not reliably capture keyboard events via `.onKeyPress` (macOS 14+) or `@FocusState`. The popover's key view hierarchy is fragile and breaks when the search field steals focus.

Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed when the popover opens and removed when it closes. This captures all key events while the popover is visible, regardless of which SwiftUI view has focus.

The monitor is installed/removed via the existing `dismissPopover` callback pattern -- add a corresponding `popoverDidAppear` callback, or install the monitor in PopoverView's `.onAppear` / `.onDisappear`.

### Component Structure

```
PopoverView
  +-- @State focusedId: String?
  +-- @State selectedIds: Set<String>
  +-- keyboardMonitor (NSEvent local monitor)
  |
  +-- header
  +-- tabBar
  +-- searchBar
  +-- sessionList
  |   +-- DotGridView (focus ring on focused dot)
  |   +-- activeSessionList (focus ring + selection highlight on rows)
  |   +-- historySessionList (focus ring + selection highlight on rows)
  +-- batchActionBar (when selectedIds.count >= 2, replaces footer)
  +-- footer (when selectedIds.count < 2)
```

## Keyboard Navigation

### Key Bindings

| Key | Action | Context |
|-----|--------|---------|
| Arrow Up | Move focus to previous session | List and dot grid |
| Arrow Down | Move focus to next session | List and dot grid |
| Arrow Left | Move focus left in grid | Dot grid only |
| Arrow Right | Move focus right in grid | Dot grid only |
| Enter / Return | Jump to focused session's window | Any focused session |
| Space | Toggle pin on focused session | Any focused session |
| Escape | Deselect all, or dismiss popover | Deselect first if selection active |
| Tab | Switch between Active/History tabs | Always |
| Cmd+A | Select all visible sessions | List view only |
| Cmd+F | Toggle search | Always |

### Focus Ring

The focused session displays a 2px teal outline (`Color(.systemTeal).opacity(0.6)`) as a rounded rectangle overlay:

```swift
.overlay(
    RoundedRectangle(cornerRadius: 6)
        .stroke(Color(.systemTeal).opacity(0.6), lineWidth: 2)
        .padding(1)
)
```

Applied to both `CompactRowView` / `ExpandedRowView` rows and `DotCellView` cells.

### Focus Behavior

- **Initial state:** No session is focused when the popover opens. First arrow key press focuses the first visible session.
- **Wrapping:** Focus wraps around. Arrow Down on the last session moves focus to the first session. Arrow Up on the first session moves focus to the last.
- **Dot grid navigation:** Arrow Up/Down move by row (4 columns). Arrow Left/Right move by one position. Wrapping applies at grid boundaries.
- **View mode switch:** Focus is maintained across list/dot grid switches when possible. If the focused session is still visible after the switch, it stays focused. If not, focus clears.
- **Tab switch:** Focus clears when switching between Active and History tabs.
- **Search:** Focus clears when search text changes. The search TextField captures keyboard input, so arrow keys only navigate sessions when the search field is not active.
- **Scroll into view:** When focus moves to an off-screen session, the `ScrollView` scrolls to reveal it. Use `ScrollViewReader` with `.scrollTo(id, anchor: .center)`.

### Conflict with Search TextField

When the search bar is visible and the TextField has focus, arrow keys should not move session focus -- they should work normally inside the text field. The keyboard monitor checks whether the search field is the first responder and skips session navigation in that case.

When the search bar is dismissed, keyboard navigation resumes immediately.

## Multi-Select

### Gestures

| Gesture | Action |
|---------|--------|
| Plain click | Jump to session (existing behavior, unchanged) |
| Cmd+Click | Toggle individual session in/out of selection |
| Shift+Click | Select range from last-selected session to clicked session |
| Cmd+A | Select all visible sessions in current tab |

### Selection Highlight

Selected sessions have a subtle background tint:

```swift
.background(Color.primary.opacity(0.08))
```

This is applied in addition to (not replacing) the existing hover and attention backgrounds. The selection highlight is always the bottom layer so it does not interfere with attention row tinting.

### Selection Behavior

- **Independence from focus:** You can arrow through sessions (moving focus) without changing selection. Cmd+Click is the only way to add/remove from selection. This matches Finder's behavior.
- **Tab switch:** Selection clears when switching between Active and History tabs.
- **View mode switch:** Selection clears when switching between list and dot grid. Multi-select only works in list view.
- **Dot grid:** Multi-select is disabled in dot grid. Cmd+Click in dot grid does nothing special (plain click behavior). The dots are too small and close together for comfortable multi-select -- list view is better suited.
- **Search filter:** If a selected session becomes hidden by a search filter, it remains in `selectedIds` but has no visual representation. If the search is cleared, the selection reappears. This prevents surprising data loss when search text changes.
- **History tab:** Multi-select works in both Active and History tabs. The most common batch action (delete old sessions) happens in History.

### Shift+Click Range Selection

Shift+Click selects all sessions between the "anchor" and the clicked session, inclusive. The anchor is the last session that was Cmd+Clicked (added to selection). If no anchor exists (e.g., first Shift+Click), the anchor defaults to the first visible session.

Range is determined by visible order (after sorting and filtering), not by session ID or creation time.

## Batch Actions

### Batch Action Bar

When `selectedIds.count >= 2`, the footer is replaced with a batch action bar:

```
  [3 selected]        [Mark Done]  [Delete]  [Deselect]
```

Layout:
- Height: same as footer (padding vertical 6, horizontal 14)
- Left: "X selected" label (size 11, secondary color)
- Right: action buttons in an HStack with spacing 8
- Background: same as footer (no special tinting)
- Transition: cross-fade with the footer using `.transition(.opacity)` wrapped in `withAnimation`

### Buttons

| Button | Label | Style | Keyboard Shortcut |
|--------|-------|-------|-------------------|
| Mark Done | "Mark Done" | size 11, secondary text | Cmd+D |
| Delete | "Delete" | size 11, red text | Delete / Backspace |
| Deselect | "Deselect" | size 11, tertiary text | Escape |

### Batch Logic

Batch actions iterate over `selectedIds` and call existing `SessionManager` methods:

```swift
// Mark Done
for id in selectedIds {
    if var session = manager.sessions.first(where: { $0.id == id }) {
        session.status = .done
        manager.updateSession(session)
    }
}
selectedIds.removeAll()

// Delete
for id in selectedIds {
    manager.deleteSession(id: id)
}
selectedIds.removeAll()
```

Each `updateSession` / `deleteSession` call writes to disk and triggers `reload()`. This is N disk writes for N sessions. For typical batch sizes (2-10 sessions), this is fast enough. If performance becomes an issue in the future, `SessionStore` could gain a batch write method, but that is not needed for v1.0.

### Delete Confirmation

When deleting 3+ sessions, show a confirmation alert:

```swift
.alert("Delete \(selectedIds.count) sessions?", isPresented: $showDeleteConfirm) {
    Button("Delete", role: .destructive) { performBatchDelete() }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This cannot be undone.")
}
```

Deleting 1-2 sessions does not require confirmation (matches existing single-session delete behavior which has no confirmation).

### Keyboard Shortcuts for Batch

Batch keyboard shortcuts only activate when `selectedIds.count >= 2`:

| Key | Action |
|-----|--------|
| Cmd+D | Mark all selected as done |
| Delete / Backspace | Delete all selected (with confirmation if 3+) |
| Escape | Clear selection (if selection active), else dismiss popover |

Escape has two behaviors: if sessions are selected, it deselects. If nothing is selected, it dismisses the popover. This double-duty feels natural -- "get me out of this state."

## Interaction Matrix

How click modifiers interact with existing behaviors:

| Click Type | Existing Behavior | New Behavior |
|------------|-------------------|--------------|
| Plain click | Jump to window | Jump to window (unchanged) |
| Cmd+Click | (none) | Toggle selection |
| Shift+Click | (none) | Range select |
| Right-click | Context menu | Context menu (unchanged) |

When sessions are selected and user plain-clicks a session:
- The click jumps to that session's window (existing behavior preserved)
- Selection is NOT cleared by plain click (matches Finder behavior where clicking an item in a selection acts on that item, not the selection)

## Edge Cases

- **Empty list:** No keyboard navigation or selection targets. Arrow keys are no-ops.
- **Single session:** Focus ring appears. Cmd+Click toggles selection but batch bar does not appear (requires 2+).
- **All sessions filtered out by search:** Focus and selection clear. Batch bar disappears.
- **Session disappears while selected:** If a session completes (status change) and moves to History while selected in Active tab, it is removed from `selectedIds` on the next render pass.
- **Popover closes and reopens:** Focus and selection reset. These are `@State`, not persisted.
- **Project group headers in list:** Arrow keys skip project headers and move between session rows only.

## Files Changed

| File | Change |
|------|--------|
| `Views/PopoverView.swift` | Add `focusedId`, `selectedIds` state; keyboard monitor setup/teardown; pass focus/selection to rows; batch action bar; Cmd+Click/Shift+Click handling |
| `Views/CompactRowView.swift` | Accept `isFocused: Bool` and `isSelected: Bool` params; render focus ring and selection highlight |
| `Views/ExpandedRowView.swift` | Accept `isFocused: Bool` and `isSelected: Bool` params; render focus ring and selection highlight |
| `Views/DotGridView.swift` | Accept `focusedId: String?`; pass `isFocused` to `DotCellView`; `DotCellView` renders focus ring |

### Not Changed

- `Session.swift` -- no model changes
- `SessionManager.swift` -- no new methods needed, existing `updateSession` and `deleteSession` suffice
- `SessionStore.swift` -- no batch operations needed for v1.0
- `AgentPingApp.swift` -- no app lifecycle changes
- `APIRouter.swift` / `APIServer.swift` -- no API changes
- `PreferencesView.swift` -- no preference changes

## Accessibility

- Focus ring provides visible keyboard focus indicator (WCAG 2.4.7)
- Selected state is communicated via `.accessibilityAddTraits(.isSelected)` on selected rows
- Batch action bar buttons have accessibility labels: "Mark X sessions as done", "Delete X sessions", "Deselect all"
- Arrow key navigation provides an alternative to mouse for all session interactions

## Rollout

- Default: keyboard navigation enabled, multi-select enabled. No preference toggle.
- No data model changes. No migration.
- No API changes.
- Revert: `git revert` -- all changes are view-layer only.
