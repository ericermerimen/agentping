# AgentsHub Design Spec

## Goal

macOS 14+ menu bar app that monitors, manages, and navigates between running Claude Code agent sessions across any terminal environment (VSCode, Ghostty, Terminal.app, etc.).

## Architecture

Three-layer design:

```
Data Layer (inputs)
  1. Process scanner: discovers claude processes, detects parent app
  2. Hook CLI: receives rich status updates from Claude Code hooks
  Both write to: ~/.agentshub/sessions/<id>.json

State Layer (core logic)
  SessionManager: watches session directory via FSEvents,
  merges process scanner + hook data, publishes @Published state

UI Layer (outputs)
  Menu bar icon (NSStatusItem) + SwiftUI popover + Preferences window
  Accessibility API for window jumping
  macOS UserNotifications for input-required alerts
```

## Tech Stack

- Swift + SwiftUI, macOS 14 Sonoma minimum
- SwiftPM for package management
- NSStatusItem for menu bar (not MenuBarExtra -- more control)
- FSEvents / DispatchSource for file watching
- macOS Accessibility API (AXUIElement) for window focus
- UserNotifications framework for alerts
- sysctl / proc for process tree inspection

## Data Flow

### Session Discovery (auto-detect)

On launch and every 10 seconds:
1. Scan running processes for `claude` binary
2. Walk process tree (ppid chain) to find parent app (Terminal, Ghostty, VSCode, etc.)
3. For each discovered process not already in session store, create skeleton JSON:
   - id: derived from PID + start time
   - status: "running"
   - app: detected parent app name
   - pid: process PID
4. For existing sessions, check if PID still alive. If not, mark "unavailable"

### Hook Integration (rich data)

Users configure Claude Code hooks in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [{
      "command": "agentshub report --session $CLAUDE_SESSION_ID --event tool-use"
    }],
    "Stop": [{
      "command": "agentshub report --session $CLAUDE_SESSION_ID --event stopped"
    }],
    "Notification": [{
      "command": "agentshub report --session $CLAUDE_SESSION_ID --event needs-input"
    }]
  }
}
```

The `agentshub report` CLI command writes/updates the session JSON file.

### Session JSON Schema

```json
{
  "id": "session-abc123",
  "name": "Backend Refactor",
  "status": "running",
  "app": "vscode",
  "pid": 12345,
  "windowId": null,
  "cwd": "/Users/eric/project",
  "file": "auth_module.ts",
  "startedAt": "2026-03-10T10:00:00Z",
  "lastEventAt": "2026-03-10T10:14:22Z",
  "notifications": true,
  "costUsd": 0.42
}
```

Status values: `running` | `needs-input` | `idle` | `done` | `error` | `unavailable`

## UI Design

### Menu Bar Icon
- NSStatusItem with SF Symbol
- Active session count as badge text
- Red dot overlay when any session has status `needs-input`

### Popover (Design 3 hybrid)

```
┌──────────────────────────────────────┐
│  [AGENTSHUB]              3 active   │
├──────────────────────────────────────┤
│  [ Running ]  [ History ]            │
├──────────────────────────────────────┤
│  * Backend Refactor    [VSCODE] 4:12 │
│  * Scaffold DB Models [GHOSTTY] 12:45│
│  o Docker Config    [TERMINAL] INPUT │
│  o Log Analysis     [GHOSTTY]  IDLE  │
├──────────────────────────────────────┤
│  + New Agent Instance                │
│  Clear Unavailable (2)               │
└──────────────────────────────────────┘
```

- Sticky header: app name + active count
- Segmented control: Running / History
- Compact rows (~32pt height): status dot + task name + app badge + elapsed/status
- Color coding: red dot = needs input, black dot = running, hollow = idle, grey = unavailable
- `INPUT` badge highlighted for sessions needing attention
- Click row: jump to window via Accessibility API
- Footer: new agent button, clear unavailable button (with count)
- Scrollable list, max ~8 visible rows before scroll

### Preferences Window

- Launch at login toggle
- Global notifications toggle (on/off)
- Per-session notification override (in popover context menu)
- Process scan interval (10s / 30s / 60s)
- Hook installation helper: button that copies hook JSON to clipboard or auto-injects into ~/.claude/settings.json
- Cost tracking toggle

## CLI Tool

Binary: `agentshub`

Commands:
- `agentshub report --session <id> --event <type> [--name <name>] [--file <file>]` -- called by hooks
- `agentshub list [--json]` -- list active sessions (for scripting)
- `agentshub status` -- one-line summary (e.g., "3 running, 1 needs input")

## Window Jumping

1. On session creation, store PID
2. Walk PID -> parent PID chain to find the app (e.g., Ghostty.app)
3. Use NSRunningApplication to find the app instance
4. Use Accessibility API (AXUIElement) to enumerate windows, match by title/PID
5. AXUIElementPerformAction(kAXRaiseAction) to focus the window
6. NSRunningApplication.activate() to bring the app forward

For VSCode: additionally can use `code --goto` URI scheme.

## Cost Tracking

Parse Claude Code local cost logs from `~/.claude/` to show per-session token spend.
Lightweight -- reads local files only, no API calls.
Displayed as small "$0.42" in the session row or detail view.

## API Status

Optional: poll Anthropic status page periodically.
Show subtle indicator in popover header if API is degraded.
Deferred if it adds complexity to v1.

## Notifications

- Uses macOS UserNotifications framework
- Triggered when session status changes to `needs-input`
- Notification action: click to jump to the session window
- Global toggle in preferences
- Per-session toggle via context menu on session row
- Respects macOS Do Not Disturb / Focus modes

## Session Lifecycle

1. **Created**: process scanner discovers PID, or hook reports first event
2. **Running**: actively processing (recent events within last 30s)
3. **Idle**: no events for 30s+ but PID alive
4. **Needs Input**: hook reports `needs-input` event
5. **Done**: hook reports `stopped` event
6. **Error**: hook reports error, or process crashed unexpectedly
7. **Unavailable**: PID no longer exists, session file stale
8. **Cleaned up**: user manually removes, or "Clear Unavailable" action

History tab shows sessions in states: done, error (last 24h, configurable).

## Deferred to v2

- WidgetKit integration
- Merge icons mode (multi-provider)
- Agent tree visualization (parent/child subagents)
- Global keyboard shortcut to open popover
- Touch Bar support
