# AgentsHub

A macOS menu bar app that monitors your Claude Code sessions, shows their status, and lets you jump to the correct window with one click.

## Features

- **Menu bar icon** with active session count and attention badge
- **Live session list** — see all running, idle, and needs-input sessions
- **Window jumping** — click a session to focus its terminal/editor window
- **macOS notifications** when a session needs your input
- **CLI tool** (`agentshub`) for scripting and Claude Code hook integration
- **FSEvents watcher** — updates instantly when session state changes
- **Preferences** — launch at login, scan interval, notification controls

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ or Swift 5.9+ toolchain

## Quick Install

```bash
git clone https://github.com/ericermerimen/agentshub.git
cd agentshub
./Scripts/install.sh
```

This builds a release binary, copies `AgentsHub.app` to `/Applications/`, and symlinks the `agentshub` CLI to `/usr/local/bin/`.

## Manual Build

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run the app directly
.build/debug/AgentsHub

# Run the CLI
.build/debug/agentshub --help
```

## Package as .app Bundle

```bash
# Debug build + app bundle
./Scripts/package_app.sh

# Release build + app bundle
./Scripts/package_app.sh --release

# With a signing identity
./Scripts/package_app.sh --release --sign "Developer ID Application: Your Name"
```

The `.app` bundle is created in the project root. Install it by dragging to `/Applications/`.

## CLI Usage

```bash
# List all sessions
agentshub list
agentshub list --json

# One-line status summary
agentshub status

# Report an event (used by hooks)
agentshub report --session SESSION_ID --event tool-use --name "My Task"
```

## Claude Code Hook Setup

AgentsHub works best with Claude Code hooks. Open the app preferences and click **"Copy Hook Config to Clipboard"**, then paste into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      { "command": "agentshub report --session $CLAUDE_SESSION_ID --event tool-use" }
    ],
    "Stop": [
      { "command": "agentshub report --session $CLAUDE_SESSION_ID --event stopped" }
    ],
    "Notification": [
      { "command": "agentshub report --session $CLAUDE_SESSION_ID --event needs-input" }
    ]
  }
}
```

## Accessibility Permission

AgentsHub uses the macOS Accessibility API to focus terminal windows when you click a session. On first launch, macOS will prompt you to grant Accessibility access in **System Settings > Privacy & Security > Accessibility**.

## Architecture

```
Sources/
├── AgentsHub/           # macOS menu bar app (SwiftUI + AppKit)
│   ├── AgentsHubApp.swift
│   ├── Views/
│   │   ├── StatusItemController.swift
│   │   ├── PopoverView.swift
│   │   ├── SessionRowView.swift
│   │   └── PreferencesView.swift
│   ├── Notifications/
│   │   └── NotificationManager.swift
│   └── Info.plist
├── AgentsHubCLI/        # CLI tool (ArgumentParser)
│   └── main.swift
└── AgentsHubCore/       # Shared library
    ├── Models/Session.swift
    ├── Store/SessionStore.swift
    ├── Manager/SessionManager.swift
    ├── Scanner/ProcessScanner.swift
    ├── Watcher/DirectoryWatcher.swift
    ├── WindowJumper/WindowJumper.swift
    └── CLI/ReportHandler.swift
```

## Data Storage

Session files are stored as JSON in `~/.agentshub/sessions/`. Each session gets its own file (`<session-id>.json`).

## License

MIT
