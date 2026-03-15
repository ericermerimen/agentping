# Implementation Plan: Keyboard Navigation, Multi-Select, and Batch Actions

**Spec:** `docs/superpowers/specs/2026-03-15-keyboard-nav-batch-actions-design.md`
**Target version:** 1.0.0

## Dependency Graph

```
  Step 1: Focus ring on row/cell views (visual foundation)
     |
     +---> Step 2: Keyboard monitor + focus navigation in PopoverView
     |        |
     |        +---> Step 3: Enter/Space/Escape/Tab key actions
     |
     +---> Step 4: Selection highlight on row views (parallel with 2-3)
              |
              +---> Step 5: Cmd+Click / Shift+Click / Cmd+A in PopoverView
                       |
                       +---> Step 6: Batch action bar + batch operations
                                |
                                +---> Step 7: Delete confirmation + final polish
```

Steps 1 and 4 can run in parallel (independent visual changes).
Steps 2-3 and 5 depend on their respective visual foundations.

## Steps

### Step 1: Focus Ring on Row and Cell Views

**Files:**
- Edit `Sources/AgentPing/Views/CompactRowView.swift`
- Edit `Sources/AgentPing/Views/ExpandedRowView.swift`
- Edit `Sources/AgentPing/Views/DotGridView.swift`

**Tasks:**
1. Add `isFocused: Bool = false` parameter to `CompactRowView`:
   ```swift
   struct CompactRowView: View {
       let session: Session
       let isFocused: Bool
       // ...
   ```
   Default to `false` so existing call sites don't break.

2. Add a focus ring overlay to `CompactRowView.body`, after the existing `.background()`:
   ```swift
   .overlay(
       Group {
           if isFocused {
               RoundedRectangle(cornerRadius: 6)
                   .stroke(Color(.systemTeal).opacity(0.6), lineWidth: 2)
                   .padding(1)
           }
       }
   )
   ```

3. Same changes to `ExpandedRowView` -- add `isFocused: Bool = false` parameter and the same overlay.

4. Add `isFocused: Bool = false` parameter to `DotCellView`. Apply a circle stroke overlay instead of rounded rect:
   ```swift
   .overlay(
       Group {
           if isFocused {
               Circle()
                   .stroke(Color(.systemTeal).opacity(0.6), lineWidth: 2)
                   .frame(width: 32, height: 32)
           }
       }
   )
   ```
   Place this on the main dot's ZStack, not the outer VStack.

5. Update `DotGridView` to accept `focusedId: String?` and pass `isFocused: session.id == focusedId` to each `DotCellView`.

**Verification:** `swift build` succeeds. No visual changes yet (all `isFocused` default to false). Manually test by hardcoding `isFocused: true` on one row to confirm the ring looks correct.

---

### Step 2: Keyboard Monitor + Focus Navigation

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift`

**Tasks:**
1. Add state properties:
   ```swift
   @State private var focusedId: String?
   @State private var selectedIds: Set<String> = []
   @State private var keyboardMonitor: Any?
   ```

2. Install `NSEvent.addLocalMonitorForEvents` on `.onAppear` and remove on `.onDisappear`:
   ```swift
   .onAppear {
       keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
           if handleKeyDown(event) { return nil }  // consumed
           return event  // pass through
       }
   }
   .onDisappear {
       if let monitor = keyboardMonitor {
           NSEvent.removeMonitor(monitor)
           keyboardMonitor = nil
       }
   }
   ```
   Place these modifiers on the outermost VStack in `body`.

3. Implement `handleKeyDown(_ event: NSEvent) -> Bool`:
   - Check `event.keyCode` for arrow keys (up=126, down=125, left=123, right=124)
   - Build a flat array of visible session IDs in display order (`visibleSessionIds`). This is the same ordering used by `sessionList` -- active sorted+grouped or history sorted, then filtered by search.
   - If `focusedId` is nil, set it to the first visible session ID (down) or last (up).
   - If `focusedId` is set, find its index in `visibleSessionIds` and move +/-1 with wrapping.
   - For dot grid: left/right move by 1, up/down move by 4 (the column count). If the target index is out of bounds, wrap.
   - Return `true` if the key was consumed.

4. Add a computed property `visibleSessionIds: [String]` that returns session IDs in the same order they appear in the list. This must mirror the logic in `activeSessionList` / `historySessionList` / `dotGridContent`:
   ```swift
   private var visibleSessionIds: [String] {
       if selectedTab == .active {
           if displayPrefs.viewMode == .dotGrid && searchText.isEmpty {
               // dot grid sort order
               return manager.activeSessions
                   .sorted { ... }
                   .map(\.id)
           } else {
               // grouped list order -- flatten groups
               return groupedActiveSessions()
                   .flatMap(\.sessions)
                   .map(\.id)
           }
       } else {
           return filteredSessions(manager.historySessions).map(\.id)
       }
   }
   ```

5. Pass `isFocused` to all row views. In `sessionRow()` and `historyRow()`:
   ```swift
   CompactRowView(
       session: session,
       isFocused: focusedId == session.id,
       // ...
   )
   ```
   Same for `ExpandedRowView`.

6. Pass `focusedId` to `DotGridView` in `dotGridContent`.

7. Wrap the `ScrollView` in a `ScrollViewReader` and call `proxy.scrollTo(focusedId, anchor: .center)` when `focusedId` changes. Add `.id(session.id)` to each row view so `ScrollViewReader` can find them.

8. Guard against search field stealing keys: in `handleKeyDown`, check if the current first responder is an `NSTextField`. If so, return `false` (let the text field handle arrow keys):
   ```swift
   if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
       return false
   }
   ```
   Note: SwiftUI's `TextField` uses an `NSTextView` as first responder, not `NSTextField`.

**Verification:** Build and run. Open popover, press Down arrow -- first session should get a teal focus ring. Arrow through all sessions. Focus wraps at boundaries. Focus clears when switching tabs. Focus clears when typing in search.

---

### Step 3: Enter, Space, Escape, Tab Key Actions

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift` (extend `handleKeyDown`)

**Tasks:**
1. Handle Enter/Return (`keyCode` 36 / 76):
   ```swift
   if let id = focusedId, let session = manager.sessions.first(where: { $0.id == id }) {
       jumpToWindow(session: session)
       return true
   }
   ```

2. Handle Space (`keyCode` 49):
   ```swift
   if let id = focusedId {
       manager.togglePin(id: id)
       return true
   }
   ```

3. Handle Escape (`keyCode` 53):
   ```swift
   if !selectedIds.isEmpty {
       selectedIds.removeAll()
       return true
   }
   // Don't consume -- let the popover dismiss via its default behavior
   return false
   ```

4. Handle Tab (`keyCode` 48):
   - Only handle when search field is not focused (check first responder).
   - Toggle `selectedTab` between `.active` and `.history`.
   - Clear `focusedId` and `selectedIds`.
   - Return `true`.

5. Handle Cmd+F (`keyCode` 3 with `.command` modifier):
   ```swift
   if event.modifierFlags.contains(.command) && event.keyCode == 3 {
       withAnimation(.easeInOut(duration: 0.15)) {
           showSearch.toggle()
           if !showSearch { searchText = "" }
       }
       return true
   }
   ```

6. Clear `focusedId` when `searchText` changes. Add `.onChange(of: searchText)`:
   ```swift
   .onChange(of: searchText) { _ in
       focusedId = nil
   }
   ```

7. Clear both `focusedId` and `selectedIds` when `selectedTab` changes. Add `.onChange(of: selectedTab)`:
   ```swift
   .onChange(of: selectedTab) { _ in
       focusedId = nil
       selectedIds.removeAll()
   }
   ```

8. Clear `selectedIds` when `displayPrefs.viewMode` changes:
   ```swift
   .onChange(of: displayPrefs.viewMode) { _ in
       selectedIds.removeAll()
   }
   ```
   Focus is preserved across view mode switches (focusedId stays if the session is still visible).

**Verification:** Build and run. Focus a session with arrows, press Enter -- window jumps. Press Space -- session pins/unpins. Press Tab -- tabs switch. Press Escape -- popover dismisses (or selection clears first if any). Cmd+F toggles search.

---

### Step 4: Selection Highlight on Row Views

**Files:**
- Edit `Sources/AgentPing/Views/CompactRowView.swift`
- Edit `Sources/AgentPing/Views/ExpandedRowView.swift`

**Tasks:**
1. Add `isSelected: Bool = false` parameter to `CompactRowView`.

2. Add selection background layer to `CompactRowView`. Modify the existing `.background()`:
   ```swift
   .background(
       Group {
           if isSelected {
               Color.primary.opacity(0.08)
           } else {
               Color.primary.opacity(isHovered ? 0.04 : 0)
           }
       }
   )
   ```
   When both selected and hovered, selected takes precedence (it is already a stronger highlight).

3. Same changes to `ExpandedRowView`. The attention background (orange/red/teal tint) stacks with selection. Add selection as an additional background layer behind the attention tint:
   ```swift
   .background {
       if isSelected {
           Color.primary.opacity(0.08)
       }
   }
   .background(rowBackground)  // existing attention tint
   ```
   The selection highlight sits behind the attention tint. For non-attention rows, the existing `isHovered` opacity handles hover, and selection adds a persistent tint.

4. Add `.accessibilityAddTraits(isSelected ? .isSelected : [])` to both row views.

**Verification:** `swift build` succeeds. Hardcode `isSelected: true` on a couple rows to verify visual appearance. The highlight should be subtle but noticeable against the dark background.

---

### Step 5: Cmd+Click, Shift+Click, Cmd+A

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift`
- Edit `Sources/AgentPing/Views/CompactRowView.swift`
- Edit `Sources/AgentPing/Views/ExpandedRowView.swift`

**Tasks:**
1. Replace the simple `onTap` closure on row views with a richer click handler that receives the `NSEvent` modifier flags. Two approaches:

   **Option A (recommended):** Keep `onTap` for plain clicks. Add `onModifierClick: ((NSEvent.ModifierFlags) -> Void)?` for modified clicks. Use a simultaneous gesture or `NSEvent` to detect modifiers.

   **Option B:** Use `.onTapGesture` and check `NSEvent.modifierFlags` (current event) at the time of tap:
   ```swift
   .onTapGesture {
       let flags = NSApp.currentEvent?.modifierFlags ?? []
       if flags.contains(.command) {
           onCommandClick?()
       } else if flags.contains(.shift) {
           onShiftClick?()
       } else {
           onTap?()
       }
   }
   ```
   This is simpler and avoids adding gesture complexity. The `NSApp.currentEvent` approach works reliably inside `NSPopover`.

   Go with Option B. Update both `CompactRowView` and `ExpandedRowView`.

2. Add callbacks to row views:
   ```swift
   var onCommandClick: (() -> Void)?
   var onShiftClick: (() -> Void)?
   ```

3. In `PopoverView`, wire up the callbacks:
   ```swift
   CompactRowView(
       session: session,
       isFocused: focusedId == session.id,
       isSelected: selectedIds.contains(session.id),
       onTap: { jumpToWindow(session: session) },
       onCommandClick: { toggleSelection(session.id) },
       onShiftClick: { extendSelection(to: session.id) },
       onReviewed: { manager.markReviewed(id: session.id) }
   )
   ```

4. Implement `toggleSelection(_ id: String)`:
   ```swift
   private func toggleSelection(_ id: String) {
       if selectedIds.contains(id) {
           selectedIds.remove(id)
       } else {
           selectedIds.insert(id)
           lastSelectedId = id  // track anchor for shift+click
       }
   }
   ```
   Add `@State private var lastSelectedId: String?` for the shift-click anchor.

5. Implement `extendSelection(to id: String)`:
   ```swift
   private func extendSelection(to id: String) {
       let ids = visibleSessionIds
       guard let targetIdx = ids.firstIndex(of: id) else { return }
       let anchorIdx = lastSelectedId.flatMap { ids.firstIndex(of: $0) } ?? 0
       let range = min(anchorIdx, targetIdx)...max(anchorIdx, targetIdx)
       for i in range {
           selectedIds.insert(ids[i])
       }
   }
   ```

6. Handle Cmd+A in `handleKeyDown`:
   ```swift
   if event.modifierFlags.contains(.command) && event.keyCode == 0 { // 'A'
       if displayPrefs.viewMode == .list || !searchText.isEmpty {
           selectedIds = Set(visibleSessionIds)
           return true
       }
   }
   ```

7. Disable multi-select in dot grid: do not pass `onCommandClick` / `onShiftClick` to `DotCellView`. Cmd+Click on a dot cell is a plain click.

8. Pass `isSelected` to row views in `sessionRow()` and `historyRow()`:
   ```swift
   isSelected: selectedIds.contains(session.id)
   ```

**Verification:** Build and run. Cmd+Click to select two sessions -- both show highlight. Shift+Click to extend range. Cmd+A selects all. Selection persists while arrowing through with keyboard. Selection clears on tab switch.

---

### Step 6: Batch Action Bar

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift`

**Tasks:**
1. Create a `batchActionBar` view:
   ```swift
   private var batchActionBar: some View {
       HStack {
           Text("\(selectedIds.count) selected")
               .font(.system(size: 11))
               .foregroundStyle(.secondary)

           Spacer()

           Button("Mark Done") { performBatchMarkDone() }
               .font(.system(size: 11))
               .foregroundStyle(.secondary)
               .buttonStyle(.plain)

           Button("Delete") { handleBatchDelete() }
               .font(.system(size: 11))
               .foregroundStyle(Color(.systemRed))
               .buttonStyle(.plain)

           Button("Deselect") {
               selectedIds.removeAll()
           }
               .font(.system(size: 11))
               .foregroundStyle(.tertiary)
               .buttonStyle(.plain)
       }
       .padding(.horizontal, 14)
       .padding(.vertical, 6)
   }
   ```

2. Replace footer conditionally in `body`:
   ```swift
   Divider().opacity(0.3)
   if selectedIds.count >= 2 {
       batchActionBar
   } else {
       footer
   }
   ```
   Wrap in `Group` if needed for animation:
   ```swift
   Group {
       if selectedIds.count >= 2 {
           batchActionBar.transition(.opacity)
       } else {
           footer.transition(.opacity)
       }
   }
   .animation(.easeInOut(duration: 0.15), value: selectedIds.count >= 2)
   ```

3. Implement `performBatchMarkDone()`:
   ```swift
   private func performBatchMarkDone() {
       let ids = selectedIds
       selectedIds.removeAll()
       for id in ids {
           if var session = manager.sessions.first(where: { $0.id == id }),
              [.running, .needsInput, .idle].contains(session.status) {
               session.status = .done
               manager.updateSession(session)
           }
       }
   }
   ```

4. Implement `performBatchDelete()`:
   ```swift
   private func performBatchDelete() {
       let ids = selectedIds
       selectedIds.removeAll()
       for id in ids {
           manager.deleteSession(id: id)
       }
   }
   ```

5. Handle batch keyboard shortcuts in `handleKeyDown`:
   ```swift
   // Cmd+D: Mark done (only when batch selected)
   if event.modifierFlags.contains(.command) && event.keyCode == 2 && selectedIds.count >= 2 {
       performBatchMarkDone()
       return true
   }

   // Delete/Backspace: Delete selected (only when batch selected)
   if (event.keyCode == 51 || event.keyCode == 117) && selectedIds.count >= 2 {
       handleBatchDelete()
       return true
   }
   ```
   `keyCode` 51 = Backspace, 117 = Forward Delete.

6. Clean up stale selections. In the `.onReceive` for the timer (or in a `.onChange` on `manager.sessions`), prune `selectedIds` to only include IDs that still exist:
   ```swift
   .onChange(of: manager.sessions) { newSessions in
       let validIds = Set(newSessions.map(\.id))
       selectedIds = selectedIds.intersection(validIds)
   }
   ```

**Verification:** Build and run. Select 3 sessions. Batch bar appears with "3 selected". Click "Mark Done" -- sessions move to history, bar disappears. Select 2, press Cmd+D -- same result. Select 2, press Delete -- sessions deleted.

---

### Step 7: Delete Confirmation + Final Polish

**Files:**
- Edit `Sources/AgentPing/Views/PopoverView.swift`

**Tasks:**
1. Add confirmation state:
   ```swift
   @State private var showDeleteConfirm = false
   ```

2. `handleBatchDelete()` checks count and either confirms or deletes directly:
   ```swift
   private func handleBatchDelete() {
       if selectedIds.count >= 3 {
           showDeleteConfirm = true
       } else {
           performBatchDelete()
       }
   }
   ```

3. Add `.alert` modifier to the outer VStack:
   ```swift
   .alert("Delete \(selectedIds.count) sessions?", isPresented: $showDeleteConfirm) {
       Button("Delete", role: .destructive) { performBatchDelete() }
       Button("Cancel", role: .cancel) {}
   } message: {
       Text("This cannot be undone.")
   }
   ```

4. Accessibility pass:
   - Add `.accessibilityLabel("Mark \(selectedIds.count) sessions as done")` to Mark Done button.
   - Add `.accessibilityLabel("Delete \(selectedIds.count) sessions")` to Delete button.
   - Add `.accessibilityLabel("Deselect all sessions")` to Deselect button.
   - Verify `.accessibilityAddTraits(.isSelected)` on selected rows (from Step 4).

5. Edge case: Escape key priority. Update the Escape handler:
   ```swift
   // Escape
   if event.keyCode == 53 {
       if !selectedIds.isEmpty {
           withAnimation { selectedIds.removeAll() }
           return true   // consumed: deselect, don't dismiss
       }
       if focusedId != nil {
           focusedId = nil
           return true   // consumed: defocus
       }
       return false  // let popover dismiss
   }
   ```
   This gives Escape three levels: deselect -> defocus -> dismiss.

6. Edge case: Ensure `lastSelectedId` is cleared when selection is cleared:
   ```swift
   // In every place selectedIds.removeAll() is called:
   selectedIds.removeAll()
   lastSelectedId = nil
   ```

7. Verify the keyboard monitor is properly cleaned up. In `.onDisappear`, nil out the reference:
   ```swift
   .onDisappear {
       if let monitor = keyboardMonitor {
           NSEvent.removeMonitor(monitor)
           keyboardMonitor = nil
       }
   }
   ```
   Also handle the case where the popover is re-opened: `.onAppear` should check if a monitor already exists before adding a new one.

8. Test matrix:
   - 0 sessions: arrow keys do nothing, Cmd+A does nothing
   - 1 session: focus ring appears, can't batch (need 2+)
   - 5 sessions: full keyboard nav + multi-select + batch
   - Mix of attention + compact rows: focus ring looks correct on both
   - Dot grid: focus ring on dots, no multi-select
   - Search active: arrow keys work in text field, not session list
   - Tab switch: focus and selection clear
   - View mode switch: selection clears, focus preserved if possible
   - Batch mark done: sessions move to History tab
   - Batch delete 2: no confirmation, immediate
   - Batch delete 5: confirmation dialog appears
   - Escape cascade: deselect -> defocus -> dismiss

**Verification:** Full manual QA pass. Build release binary: `swift build -c release`.

## Review Checkpoints

- After Step 1: Focus ring renders correctly on hardcoded `isFocused: true`
- After Step 3: Full keyboard navigation works (arrows, enter, space, escape, tab)
- After Step 5: Multi-select works (Cmd+Click, Shift+Click, Cmd+A)
- After Step 6: Batch action bar appears and batch operations work
- After Step 7: Delete confirmation, accessibility, edge cases all verified

## Implementation Notes

### NSEvent Key Codes Reference

| Key | keyCode |
|-----|---------|
| Arrow Up | 126 |
| Arrow Down | 125 |
| Arrow Left | 123 |
| Arrow Right | 124 |
| Return | 36 |
| Enter (numpad) | 76 |
| Space | 49 |
| Tab | 48 |
| Escape | 53 |
| Backspace | 51 |
| Forward Delete | 117 |
| A | 0 |
| D | 2 |
| F | 3 |

### Why NSEvent Monitor Instead of SwiftUI .onKeyPress

SwiftUI's `.onKeyPress` (macOS 14+) requires the view to be focused within the SwiftUI focus system. Inside an `NSPopover`, focus is unpredictable:
- The `NSHostingView` may or may not be the key view.
- `TextField` steals focus and does not return it when dismissed.
- `.focusable()` on the VStack conflicts with the scroll view's focus handling.

`NSEvent.addLocalMonitorForEvents` is the standard AppKit pattern for this. It reliably captures all key events sent to the application, and the monitor can selectively consume events (return nil) or pass them through (return the event). This is the same approach used by Spotlight, Alfred, and other popover-based macOS UIs.

### Performance Consideration

Batch delete/mark-done calls `manager.deleteSession` / `manager.updateSession` in a loop, each of which calls `store.write()` + `reload()`. For N sessions, this is N file writes and N full reloads. This is fine for typical batch sizes (2-10). If users report lag with very large batches, the fix would be to add a batch method to `SessionManager` that writes all files then reloads once. Not needed for v1.0.
