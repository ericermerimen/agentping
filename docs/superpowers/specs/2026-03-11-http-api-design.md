# AgentPing HTTP API + Hover Preview Design

## Goal

Embed a lightweight HTTP API server in the AgentPing menu bar app so any AI coding tool (not just Claude Code) can report sessions. Add provider/model tracking and a hover preview for sessions.

## Architecture

```
Before:
  Claude Hook -> shell exec -> agentping CLI -> write JSON -> FSEvents -> UI

After:
  Claude Hook -> shell exec -> agentping CLI -> HTTP POST :19199 -> write JSON -> UI
  Any tool   -> HTTP POST :19199 -> write JSON -> UI
  CLI offline -> agentping CLI -> write JSON directly (fallback)
```

HTTP server runs inside the existing menu bar app process using `NWListener` (Network.framework). No new dependencies. No separate daemon.

## HTTP Server

### Technology

- `NWListener` (Network.framework) for TCP accept
- Minimal HTTP/1.1 parser (~50 lines): request line + Content-Length header + body
- Localhost only (`127.0.0.1`), no TLS
- Connection-close after each response (no keep-alive/pipelining)
- GCD serial queue for request processing
- 5s read timeout, 8KB max headers, 1MB max body

### Default Port

`19199` -- configurable via Preferences (stored in UserDefaults as `apiPort`).

### Endpoints

#### POST /v1/report

Report a session event. Replaces direct file writes.

```json
{
  "session_id": "abc-123",
  "event": "tool-use",
  "name": "my-project",
  "cwd": "/Users/foo/project",
  "file": "main.swift",
  "app": "Ghostty",
  "transcript_path": "/path/to/transcript.jsonl",
  "provider": "Claude",
  "model": "Opus 4.6",
  "pid": 12345
}
```

Required: `session_id`, `event`. All others optional.

Events: `tool-use`, `needs-input`, `stopped`, `error`.

Response: `200 OK` with updated session JSON, or `400` with error.

#### GET /v1/sessions

List all sessions.

Response: `200 OK` with JSON array of sessions.

Optional query: `?status=running` to filter.

#### GET /v1/sessions/:id

Get a single session.

Response: `200 OK` with session JSON, or `404`.

#### DELETE /v1/sessions/:id

Delete a session.

Response: `204 No Content`, or `404`.

#### GET /v1/health

Health check.

Response: `200 OK` with `{"status":"ok","version":"0.6.0","port":19199}`.

### Error Responses

```json
{
  "error": "description of what went wrong"
}
```

Status codes: 400 (bad request), 404 (not found), 413 (body too large), 500 (internal error).

## Session Model Changes

Two new optional fields on `Session`:

```swift
var provider: String?   // "Claude", "Copilot", "Cursor", "Aider", etc.
var model: String?      // "Opus 4.6", "GPT-5.3-Codex", "claude-sonnet-4-6", etc.
```

Backward compatible -- existing session JSON files without these fields decode with nil.

### Auto-extraction for Claude Code

ReportHandler already reads the transcript. Extract model from the last assistant message:

```json
{"type":"assistant","model":"claude-opus-4-6",...}
```

Map to: `provider = "Claude"`, `model = "Opus 4.6"` (humanized).

Model ID mapping:
- `claude-opus-4-6` -> "Opus 4.6"
- `claude-sonnet-4-6` -> "Sonnet 4.6"
- `claude-haiku-4-5-*` -> "Haiku 4.5"
- Unknown -> raw model ID

For non-Claude tools, clients pass `provider` and `model` directly in the report payload.

## CLI Changes

The CLI (`agentping report`) changes from direct file write to HTTP client:

1. Try `POST http://127.0.0.1:{port}/v1/report` (read port from `~/.agentping/port` or default 19199)
2. If HTTP fails (connection refused, timeout), fall back to direct file write via ReportHandler
3. Other commands (`list`, `status`, `delete`, `clear`) also try HTTP first, fall back to file reads

The app writes the active port to `~/.agentping/port` on server start, deletes on shutdown.

## Preferences Changes

Add to PreferencesView under a new "API" section:

- **API Port**: text field, default 19199, validated as 1024-65535
- **Show port info**: label showing "API running on localhost:19199"

## Hover Preview

New `SessionHoverView.swift` -- appears on mouse hover over a session row.

Content:
- Provider + Model label (e.g., "Claude Opus 4.6") or "Unknown" if not set
- Status badge + elapsed time
- Task description (full text, not truncated to row width)
- Context % bar (wider than row version)
- Cost (if tracking enabled)
- cwd path

Implementation: `.onHover` modifier on SessionRowView triggers a `.popover` anchored to the row. Dismiss on mouse exit. Small delay (0.3s) before showing to avoid flicker.

Size: ~280x180, compact.

## New Files

| File | Target | Purpose |
|------|--------|---------|
| `Sources/AgentPingCore/API/APIServer.swift` | AgentPingCore | NWListener HTTP server |
| `Sources/AgentPingCore/API/HTTPParser.swift` | AgentPingCore | Minimal HTTP request/response types + parsing |
| `Sources/AgentPingCore/API/APIRouter.swift` | AgentPingCore | Route matching + handler dispatch |
| `Sources/AgentPing/Views/SessionHoverView.swift` | AgentPing | Hover preview popover |

## Modified Files

| File | Change |
|------|--------|
| `Session.swift` | Add `provider`, `model` optional fields |
| `ReportHandler.swift` | Extract model from Claude transcripts |
| `SessionManager.swift` | Add `session(byId:)` lookup method |
| `main.swift` (CLI) | HTTP-first with file fallback |
| `PreferencesView.swift` | Add API port setting |
| `AgentPingApp.swift` | Start APIServer on launch |
| `SessionRowView.swift` | Add hover trigger for preview |

## Testing

- Unit tests for HTTPParser (malformed requests, partial reads, large bodies)
- Unit tests for model name extraction/mapping
- Unit tests for API router (path matching, method validation)
- Integration test: POST report -> verify session file written
- Integration test: GET sessions -> verify JSON response
- CLI fallback test: verify file write when HTTP unavailable
- Manual test: `curl` all endpoints
- Manual test: hover preview appearance and dismiss
- Backward compat: verify old session JSON files still load
