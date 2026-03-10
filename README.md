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

## Install

### Homebrew (recommended)

```bash
brew tap ericermerimen/tap
brew install agentshub
```

Then start the menu bar app:

```bash
open $(brew --prefix)/AgentsHub.app
# or use brew services to auto-start on login:
brew services start agentshub
```

### Download from GitHub Releases

No Xcode required — just download the pre-built `.app`:

1. Go to [Releases](https://github.com/ericermerimen/agentshub/releases/latest)
2. Download `AgentsHub-vX.X.X-macos.tar.gz`
3. Extract and install:

```bash
tar xzf AgentsHub-*.tar.gz
cp -r AgentsHub.app /Applications/
# Optional: add CLI to your PATH
ln -sf /Applications/AgentsHub.app/Contents/MacOS/agentshub /usr/local/bin/agentshub
```

4. Open from `/Applications/` or run `open /Applications/AgentsHub.app`

### Build from Source

Only needed if you want to develop or modify AgentsHub. Requires Xcode 15+ or Swift 5.9+.

```bash
git clone https://github.com/ericermerimen/agentshub.git
cd agentshub
./Scripts/install.sh
```

Or manually:

```bash
swift build -c release
./Scripts/package_app.sh --release
cp -r AgentsHub.app /Applications/
```

## CLI Usage

The `agentshub` CLI is bundled inside the `.app` (no separate install needed if you symlinked it).

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

## Uninstall

**Homebrew:**
```bash
brew services stop agentshub
brew uninstall agentshub
```

**Manual:**
```bash
rm -rf /Applications/AgentsHub.app
rm -f /usr/local/bin/agentshub
rm -rf ~/.agentshub
```

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
