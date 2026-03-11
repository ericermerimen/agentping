# AgentPing

## What is this

AgentPing (formerly AgentsHub) is a macOS menu bar app for monitoring Claude Code sessions in real time. It shows session status, lets you jump to terminal windows, sends notifications when agents need input, and tracks context window usage and cost.

The project was renamed from AgentsHub to AgentPing. The local directory is still `/Users/eric.er/agentshub` but the GitHub repo is `ericermerimen/agentping`.

## Tech stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit (menu bar popover)
- **Platform**: macOS 14 (Sonoma)+
- **Build**: Swift Package Manager (no Xcode project)
- **Dependencies**: swift-argument-parser (Apple, v1.6.2) -- only dependency
- **CI**: GitHub Actions (release on tag push)
- **Distribution**: Homebrew tap (`ericermerimen/tap/agentping`), curl installer, GitHub Releases

## Architecture

Three Swift targets in a single Swift package:

```
Sources/
├── AgentPing/          # macOS menu bar GUI app (SwiftUI + AppKit)
│   ├── AgentPingApp.swift       # AppDelegate, global hotkey, notifications, popover
│   ├── Views/
│   │   ├── PopoverView.swift    # Main UI: tabs, search, project grouping, context menu
│   │   ├── SessionRowView.swift # Session list row with status, context bar, cost
│   │   └── PreferencesView.swift # Settings window
│   └── Notifications/
│       └── NotificationManager.swift  # macOS notification handling
├── AgentPingCLI/       # CLI tool (ArgumentParser)
│   └── main.swift      # Commands: report, list, status, clear, delete
└── AgentPingCore/      # Shared library (no UI)
    ├── Models/Session.swift           # Session data model + JSON codable
    ├── Store/SessionStore.swift       # File-based JSON persistence (~/.agentping/sessions/)
    ├── Manager/SessionManager.swift   # Session lifecycle, sync, auto-purge
    ├── Scanner/ProcessScanner.swift   # Detects running Claude processes via ps
    ├── Watcher/DirectoryWatcher.swift # FSEvents watcher for live updates
    ├── WindowJumper/WindowJumper.swift # Accessibility API window focus
    ├── CLI/ReportHandler.swift        # Processes hook events, reads transcripts
    └── API/
        ├── HTTPParser.swift           # Minimal HTTP/1.1 request/response parser
        ├── APIRouter.swift            # REST route handling + input validation
        └── APIServer.swift            # NWListener TCP server (localhost only)
```

## How it works

1. Claude Code hooks call `agentping report --session ID --event TYPE` on each tool use, stop, and notification
2. The CLI posts to the HTTP API (localhost:19199) or falls back to writing JSON files directly
3. The app's embedded API server (`APIServer` + `APIRouter`) processes reports and writes session files
4. `DirectoryWatcher` detects the file change via FSEvents
5. `SessionManager.reload()` reads all session files
6. The SwiftUI popover updates reactively via `@ObservedObject`
7. Clicking a session uses `WindowJumper` (Accessibility API) to focus the right terminal window

### HTTP API (v0.6.0+)

The app embeds a localhost HTTP server (default port 19199, configurable in Preferences) for session reporting. Any local tool can integrate by posting to the API.

- `POST /v1/report` -- create/update a session
- `GET /v1/sessions` -- list all sessions (optional `?status=` filter)
- `GET /v1/sessions/:id` -- get a single session
- `DELETE /v1/sessions/:id` -- delete a session
- `GET /v1/health` -- server health check

Port is written to `~/.agentping/port` for discovery. CLI reads this file to find the running server.

## Key features

- **Active/History tabs** with attention badge counts
- **Project grouping** -- sessions grouped by cwd directory name
- **Search/filter** -- filter by name, project, task, app
- **Pin sessions** -- pinned sessions float to top
- **Global hotkey** -- Ctrl+Option+A toggles the popover
- **Context menu** -- right-click: jump, copy path, open transcript, open terminal, pin, mark done, delete
- **Notifications** -- needs-input, error, done, context window warning (80%+)
- **Context bar** -- visual progress bar for context window usage (green/orange/red)
- **Cost tracking** -- optional per-session and total cost display
- **Auto-purge** -- finished sessions older than 24h removed on launch
- **CLI** -- `agentping list/status/report/clear/delete`
- **HTTP API** -- localhost REST API for third-party tool integration (port 19199)
- **Provider/model tracking** -- auto-extracted from Claude transcripts, manual via API for other tools
- **Session hover preview** -- shows model, status, task, context, cost, path on hover

## GitHub repos

- **Main repo**: `ericermerimen/agentping` (was `ericermerimen/agentshub`)
- **Homebrew tap**: `ericermerimen/homebrew-tap`
- **Old repo**: `ericermerimen/agentshub` (still exists, should be archived)

## Secrets

- `TAP_TOKEN` -- fine-grained GitHub PAT with Contents:RW on `homebrew-tap` repo. Used by release workflow to auto-update the Homebrew formula.

## Release process

```bash
git tag v0.X.0
git push origin v0.X.0
```

This triggers `.github/workflows/release.yml` which:
1. Builds universal binary (arm64 + x86_64)
2. Creates `.app` bundle via `Scripts/package_app.sh`
3. Creates tarball with LICENSE (prevents Homebrew directory stripping)
4. Publishes GitHub Release with SHA256 checksums
5. Auto-updates `homebrew-tap` formula with new URL + SHA (stable tags only)

Beta/RC tags (`v0.X.0-beta.N`, `v0.X.0-rc.N`) are marked as prerelease and skip the Homebrew tap update.

## Marketing site

- `site/index.html` -- dark-themed landing page
- Auto-deployed to GitHub Pages via `.github/workflows/pages.yml`
- URL: `https://ericermerimen.github.io/agentping/`
- Accent color: teal (#06b6d4)

## Data storage

- Sessions: `~/.agentping/sessions/<id>.json` (0700 dir permissions)
- Preferences: macOS UserDefaults (`launchAtLogin`, `notificationsEnabled`, `scanInterval`, `costTrackingEnabled`)

## Build commands

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Tests (requires Xcode toolchain for XCTest)
./Scripts/package_app.sh # Build .app bundle
./Scripts/install.sh     # Build + install to /Applications
```

## Security model

**Threat model: trusted local processes.** The HTTP API binds to localhost only (`acceptLocalOnly = true`) and has no authentication. Any process running as the current user can create, read, modify, or delete sessions. This is the same trust model as Docker Desktop, webpack-dev-server, and similar dev tools.

Accepted risk: a malicious local process could forge session reports or delete sessions. This is low-impact (monitoring data only, no secrets) and adding auth would add friction for the primary use case (CLI hooks calling the API thousands of times per session).

**Mitigations in place:**
- **Path traversal**: Session IDs are sanitized in `SessionStore.sanitizeId()` (strips `/`, `\`, `..`, null bytes). API layer also rejects invalid IDs at the boundary before they reach the store.
- **Command injection**: "Open in Terminal" uses `Process` + `open -a Terminal` with argument passing, not AppleScript string interpolation. Directory existence is validated before execution.
- **Request size**: API server rejects requests >1MB+8KB.
- **Connection timeout**: 5s timeout on incomplete requests.
- **File permissions**: Session directory created with 0700 permissions.

## Known issues / notes

- Sandbox is disabled (required for Accessibility API / window jumping)
- Context window size is hardcoded to 200K tokens (Claude Opus)
- Stale session detection uses 5-minute timeout + process check
- Tests require Xcode toolchain (XCTest not available with plain swift CLI)
- The local directory is still named `agentshub` -- only the repo and all code references are renamed to `agentping`
