# Session Close Detection via SessionEnd Hook

**Date:** 2026-03-14
**Status:** Approved

## Problem

Sessions only move to the History tab via two mechanisms:
1. User manually marks them "Done" (right-click context menu)
2. Auto-sync detects no events for 5+ minutes AND process is dead (`kill(pid, 0)`)

This means closed sessions linger in the Active tab for minutes after the user has already exited Claude Code. The Active tab becomes cluttered with ghost sessions that are no longer running.

## Solution

Use the Claude Code `SessionEnd` hook event to instantly detect when a session is truly closed and move it to History immediately.

### SessionEnd hook event

Claude Code fires `SessionEnd` when a session terminates:
- `reason: "prompt_input_exit"` -- user exits at the prompt (Ctrl+C, Ctrl+D, typing "exit")
- `reason: "clear"` -- user runs `/clear`
- `reason: "logout"` -- user logs out
- `reason: "other"` -- terminal closed, process killed

The hook fires before the process fully dies, giving ~1.5s for execution.

## Design

### 1. New event type: `session-end`

Add `"session-end"` to `SessionStatus.from(event:current:)`. When received, return `.done` regardless of current status.

**File:** `Sources/AgentPingCore/Models/Session.swift`

```swift
case "session-end": return .done
```

### 2. Remove auto-sync stale-to-done logic

The `sync()` method in `SessionManager` currently marks sessions as `.done` when idle >5min + process dead. Remove this behavior entirely.

Sessions stay in Active until either:
- `SessionEnd` fires (instant, definitive)
- User manually marks done via context menu

Keep the `sync()` timer for `reload()` (re-reading session files from disk). Only remove the stale-to-done state transition.

**File:** `Sources/AgentPingCore/Manager/SessionManager.swift`

Remove the for-loop in `sync()` that checks staleness and process aliveness (lines ~48-63). Keep `reload()` call.

### 3. Update hook config template

Add `SessionEnd` to the hook config that "Copy Hook Config" copies to clipboard.

**File:** `Sources/AgentPing/Views/PreferencesView.swift`

```json
{
  "hooks": {
    "PostToolUse": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event tool-use'"}],
    "Stop": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event stopped'"}],
    "Notification": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event needs-input'"}],
    "SessionEnd": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event session-end'"}]
  }
}
```

### 4. Hook detection + persistent nudge

On app launch and periodically (piggyback on existing sync timer), read `~/.claude/settings.json` and check whether a `SessionEnd` hook referencing `agentping` exists.

If missing, show a persistent `(!)` indicator:
- In the popover header area (visible at all times)
- In Preferences > Integrations tab as an inline warning message
- The indicator disappears only when the hook is actually detected on a subsequent check

**Detection logic (new method on SessionManager or a dedicated HookDetector):**

```swift
static func isSessionEndHookConfigured() -> Bool {
    let settingsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    guard let data = try? Data(contentsOf: settingsPath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hooks = json["hooks"] as? [String: Any],
          let sessionEnd = hooks["SessionEnd"] as? [[String: Any]] else {
        return false
    }
    return sessionEnd.contains { entry in
        (entry["command"] as? String)?.contains("agentping") == true
    }
}
```

**Published property for UI binding:**

```swift
@Published public private(set) var isSessionEndHookMissing: Bool = true
```

Updated during `sync()` calls.

### 5. UI for missing hook warning

**PopoverView.swift -- header area:**

When `manager.isSessionEndHookMissing` is true, show a tappable `(!)` badge or inline banner:

> "SessionEnd hook not configured. Open Preferences to set up instant close detection."

Tapping opens Preferences to the Integrations tab.

**PreferencesView.swift -- Integrations tab:**

When hook is missing, show a warning section above the existing hook config:

> "AgentPing works best with the SessionEnd hook. Click 'Copy Hook Config' below and paste into ~/.claude/settings.json"

## Files touched

| File | Change |
|---|---|
| `Sources/AgentPingCore/Models/Session.swift` | Add `"session-end"` case → `.done` |
| `Sources/AgentPingCore/Manager/SessionManager.swift` | Remove stale→done logic, add hook detection, add `isSessionEndHookMissing` property |
| `Sources/AgentPing/Views/PreferencesView.swift` | Update hook config string (4 hooks), add missing-hook warning |
| `Sources/AgentPing/Views/PopoverView.swift` | Show `(!)` badge when hook not detected |
| `Sources/AgentPing/AgentPingApp.swift` | No changes needed (sync timer already exists, hook check piggybacks on it) |

## What doesn't change

- Session model structure (no new fields or status values)
- Active/History tab filtering (`.done`/`.error` = History, everything else = Active)
- ProcessScanner, DirectoryWatcher, FSEvents watcher
- "Mark as Done" context menu (stays as manual fallback)
- Window jumping, notifications, cost tracking
- API endpoints

## Edge cases

| Scenario | Behavior |
|---|---|
| `kill -9` on Claude process (hook can't fire) | Session stays in Active. User can manually mark done. |
| SessionEnd fires but API server is down | CLI falls back to writing JSON file directly. Session still moves to History. |
| User has old 3-hook config | Persistent `(!)` nudge until they update. Sessions still work but rely on manual "Mark as Done" for close detection. |
| `/clear` in Claude Code | SessionEnd fires with `reason: "clear"`. Session moves to History. |
| Multiple rapid SessionEnd events | Idempotent -- marking an already-done session as done is a no-op. |
