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

### One-line install (recommended)

No Xcode required — downloads the pre-built `.app` from GitHub Releases:

```bash
curl -fsSL https://raw.githubusercontent.com/ericermerimen/agentshub/main/Scripts/install-remote.sh | bash
```

Then start the app:

```bash
open /Applications/AgentsHub.app
```

### Homebrew

> **Note:** Requires creating the [homebrew-tap](https://github.com/ericermerimen/homebrew-tap) repo first. See [Homebrew Setup](#homebrew-setup) below.

```bash
brew tap ericermerimen/tap
brew install agentshub
```

### Download manually from GitHub Releases

1. Go to [Releases](https://github.com/ericermerimen/agentshub/releases/latest)
2. Download `AgentsHub-vX.X.X-macos.tar.gz`
3. Extract and install:

```bash
tar xzf AgentsHub-*.tar.gz
cp -r AgentsHub.app /Applications/
ln -sf /Applications/AgentsHub.app/Contents/MacOS/agentshub /usr/local/bin/agentshub
```

### Build from source

Only needed if you want to develop or modify AgentsHub. Requires Xcode 15+ or Swift 5.9+.

```bash
git clone https://github.com/ericermerimen/agentshub.git
cd agentshub
./Scripts/install.sh
```

## Creating a Release

Tag a version to trigger the GitHub Actions build:

```bash
git tag v0.1.0
git push origin v0.1.0
```

This builds a universal binary (arm64 + x86_64), packages the `.app`, and publishes it as a GitHub Release — no Xcode needed on the user's machine.

## Homebrew Setup

To enable `brew install`, create a **separate** repo called [`homebrew-tap`](https://github.com/ericermerimen/homebrew-tap) and copy the formula:

```bash
# Create the tap repo on GitHub, then:
gh repo create ericermerimen/homebrew-tap --public
git clone https://github.com/ericermerimen/homebrew-tap.git
mkdir -p homebrew-tap/Formula
cp HomebrewFormula/agentshub.rb homebrew-tap/Formula/agentshub.rb
cd homebrew-tap && git add . && git commit -m "Add agentshub formula" && git push
```

After a release, update the `url` and `sha256` in the formula to match the new release tarball.

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
