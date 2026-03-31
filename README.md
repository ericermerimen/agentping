# AgentPing

A macOS menu bar app that monitors your Claude Code sessions, shows their status, and lets you jump to the correct window with one click.

*Want a desktop pet version? Check out [AgentPong](https://github.com/ericermerimen/agentpong) -- a pixel art husky that watches your sessions from a tiny floating office.*

## Features

- **Menu bar icon** with active session count and attention badge
- **Live session list** -- see all running, idle, and needs-input sessions at a glance
- **Active / History tabs** -- triage active work, review finished sessions separately
- **Window jumping** -- click a session to focus its terminal/editor window
- **Global hotkey** -- `Ctrl+Option+A` toggles the popover from anywhere
- **macOS notifications** -- alerts when a session needs input, hits an error, or finishes
- **Context menu** -- right-click to copy path/session ID, open transcript, mark done, or delete
- **Context window bar** -- see how much of Claude's context each session has consumed
- **Cost tracking** -- per-session cost display with streaming deduplication and integer nanosecond math (enable in Preferences)
- **Externalized pricing** -- `~/.agentping/pricing.json` with per-provider rates, auto-written on first launch, Sonnet tiered pricing at 200K threshold
- **OAuth quota** -- reads Claude Code credentials from Keychain or file, shows session/weekly quota % and monthly spend in popover footer
- **Bedrock support** -- detects `anthropic.*` model ID prefix, strips version suffixes, provider-aware pricing lookup
- **Session grouping** -- sessions grouped by project directory
- **Auto-purge** -- finished sessions older than 24h are cleaned up automatically
- **Search** -- filter sessions by name, project, or task
- **CLI tool** (`agentping`) for scripting and Claude Code hook integration
- **HTTP API** -- localhost REST API (port 19199) for third-party tool integration
- **Provider/model tracking** -- auto-extracted from Claude transcripts, settable via API for other tools
- **Session hover preview** -- hover a session to see model, status, task, context, cost, and path
- **FSEvents watcher** -- updates in real time when session state changes
- **Preferences** -- launch at login, scan interval, notification controls, API port

## Requirements

- macOS 14 (Sonoma) or later

## Install

### Homebrew (recommended)

```bash
brew install ericermerimen/tap/agentping
brew services start agentping
```

This launches AgentPing and auto-starts it on login. To upgrade:

```bash
brew upgrade agentping && brew services restart agentping
```

### One-line install

Downloads the pre-built `.app` from GitHub Releases. No Xcode required:

```bash
curl -fsSL https://raw.githubusercontent.com/ericermerimen/agentping/main/Scripts/install-remote.sh | bash
open ~/Applications/AgentPing.app
```

### Manual download

1. Go to [Releases](https://github.com/ericermerimen/agentping/releases/latest)
2. Download `AgentPing-vX.X.X-macos.tar.gz`
3. Extract and install:

```bash
tar xzf AgentPing-*.tar.gz
mkdir -p ~/Applications
cp -r AgentPing.app ~/Applications/
open ~/Applications/AgentPing.app
```

### Build from source

For contributors and developers. Requires Xcode 15+ or Swift 5.9+.

```bash
git clone https://github.com/ericermerimen/agentping.git
cd agentping
./Scripts/install.sh
```

## After install

1. **Grant Accessibility access** when prompted (System Settings > Privacy & Security > Accessibility)
2. Open AgentPing **Preferences** > click **"Copy Hook Config to Clipboard"**
3. Paste into `~/.claude/settings.json`
4. Restart your Claude Code sessions -- AgentPing will start tracking them

## CLI Usage

The `agentping` CLI is bundled inside the `.app` (no separate install needed if you symlinked it).

```bash
# List all sessions
agentping list
agentping list --json

# One-line status summary
agentping status

# Report an event (used by hooks)
agentping report --session SESSION_ID --event tool-use --name "My Task"

# Clear finished sessions from history
agentping clear --all
agentping clear --older-than 12  # hours

# Delete a specific session
agentping delete SESSION_ID
```

## HTTP API

When the app is running, a localhost HTTP API is available for any tool to report sessions:

```bash
# Report a session event
curl -X POST http://localhost:19199/v1/report \
  -H "Content-Type: application/json" \
  -d '{"session_id":"my-session","event":"running","name":"My Task","provider":"Copilot","model":"GPT-4o"}'

# List all sessions
curl http://localhost:19199/v1/sessions

# Get a single session
curl http://localhost:19199/v1/sessions/my-session

# Delete a session
curl -X DELETE http://localhost:19199/v1/sessions/my-session

# Health check
curl http://localhost:19199/v1/health
```

The port is configurable in Preferences and written to `~/.agentping/port` for discovery. The CLI uses the API when the app is running, falling back to direct file writes when it's not.

## Claude Code Hook Setup

AgentPing works best with Claude Code hooks. Open the app preferences and click **"Copy Hook Config to Clipboard"**, then paste into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      { "command": "bash -c 'agentping report --session $(jq -r .session_id) --event tool-use'" }
    ],
    "Stop": [
      { "command": "bash -c 'agentping report --session $(jq -r .session_id) --event stopped'" }
    ],
    "SubagentStop": [
      { "command": "bash -c 'agentping report --session $(jq -r .session_id) --event tool-use'" }
    ],
    "Notification": [
      { "command": "bash -c 'agentping report --session $(jq -r .session_id) --event needs-input'" }
    ],
    "SessionEnd": [
      { "command": "bash -c 'agentping report --session $(jq -r .session_id) --event session-end'" }
    ]
  }
}
```

## Pricing Configuration

AgentPing ships with built-in pricing for Anthropic and Bedrock providers. On first launch, it writes a default config to `~/.agentping/pricing.json` that you can edit:

```json
{
  "version": 1,
  "models": [
    {
      "model": "sonnet",
      "provider": "anthropic",
      "pricing": { "input": 3.0, "output": 15.0, "cacheRead": 0.30, "cacheWrite": 3.75 },
      "tieredThreshold": 200000,
      "tieredPricing": { "input": 6.0, "output": 30.0, "cacheRead": 0.60, "cacheWrite": 7.50 }
    }
  ]
}
```

Rates are per million tokens. Sonnet uses tiered pricing -- rates double above the `tieredThreshold` (200K tokens). Bedrock models are detected automatically from `anthropic.*` model ID prefixes.

## OAuth Quota

If you use Claude Code with an Anthropic account (OAuth), AgentPing can show your quota usage in the popover footer. It reads credentials from:

1. macOS Keychain (service: `Claude Code-credentials`)
2. `~/.claude/.credentials.json`

When credentials are found, the popover footer shows session (5-hour) and weekly (7-day) quota percentages plus monthly spend. Data is cached for 5 minutes. No configuration needed -- it works automatically if you're logged in to Claude Code.

## Keyboard Shortcut

Press `Ctrl+Option+A` from anywhere to toggle the AgentPing popover. No need to click the menu bar icon.

## Accessibility Permission

AgentPing uses the macOS Accessibility API to focus terminal windows when you click a session. On first launch, macOS will prompt you to grant Accessibility access in **System Settings > Privacy & Security > Accessibility**.

## Uninstall

**Homebrew:**
```bash
brew services stop agentping
brew uninstall agentping
```

**Manual:**
```bash
rm -rf /Applications/AgentPing.app
rm -f /usr/local/bin/agentping
rm -rf ~/.agentping
```

## Creating a Release

Tag a version to trigger the GitHub Actions build:

```bash
git tag v0.1.0
git push origin v0.1.0
```

This builds a universal binary (arm64 + x86_64), packages the `.app`, publishes it as a GitHub Release, auto-generates the Sparkle `appcast.xml`, and updates the Homebrew formula (with retry + rebase for race conditions).

Beta/RC tags (e.g. `v0.7.0-beta.1`) are published as prereleases and do not update the Homebrew formula or appcast.

To enable automatic Homebrew tap updates, add a `TAP_TOKEN` secret to your repo (a personal access token with `repo` scope for `ericermerimen/homebrew-tap`).

## Architecture

```
Sources/
├── AgentPing/           # macOS menu bar app (SwiftUI + AppKit)
│   ├── AgentPingApp.swift
│   ├── HookDetector.swift
│   ├── UpdateChecker.swift
│   ├── Views/
│   │   ├── PopoverView.swift
│   │   ├── SessionRowView.swift
│   │   ├── SessionHoverView.swift
│   │   └── PreferencesView.swift
│   ├── Notifications/
│   │   └── NotificationManager.swift
│   ├── Assets/
│   └── Info.plist
├── AgentPingCLI/        # CLI tool (ArgumentParser)
│   └── main.swift
└── AgentPingCore/       # Shared library
    ├── Models/
    │   ├── Session.swift
    │   └── PricingConfig.swift
    ├── Store/SessionStore.swift
    ├── Manager/SessionManager.swift
    ├── Scanner/ProcessScanner.swift
    ├── Watcher/DirectoryWatcher.swift
    ├── WindowJumper/WindowJumper.swift
    ├── CLI/ReportHandler.swift
    └── API/
        ├── HTTPParser.swift
        ├── APIRouter.swift
        ├── APIServer.swift
        └── OAuthFetcher.swift
```

## Security

The HTTP API binds to **localhost only** and is unauthenticated. The threat model assumes trusted local processes -- any process running as the current user can interact with the API. This is consistent with similar developer tools (Docker Desktop, webpack-dev-server, etc.).

- Session IDs are sanitized to prevent path traversal
- "Open in Terminal" uses safe argument passing (no shell/AppleScript string interpolation)
- Request size is capped at ~1MB; connections time out after 5 seconds
- Session directory uses owner-only permissions (0700)

## Data Storage

Session files are stored as JSON in `~/.agentping/sessions/`. Each session gets its own file (`<session-id>.json`). The directory is created with owner-only permissions (0700).

Pricing configuration is stored at `~/.agentping/pricing.json` (auto-written on first launch with defaults).

## License

[PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) -- free to use, modify, and share for noncommercial purposes.
