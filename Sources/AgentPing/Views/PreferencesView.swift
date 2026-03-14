import SwiftUI
import AppKit
import ServiceManagement
import AgentPingCore

enum PreferencesTab: Int, CaseIterable {
    case general = 0
    case integrations = 1
    case about = 2

    var title: String {
        switch self {
        case .general: return "General"
        case .integrations: return "Integrations"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .integrations: return "link"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var manager: SessionManager
    @ObservedObject var hookDetector: HookDetector
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar-style tab bar
            HStack(spacing: 0) {
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 18))
                                if tab == .integrations && hookDetector.isSessionEndHookMissing {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -2)
                                }
                            }
                            Text(tab.title)
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(width: 72, height: 48)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                                .padding(2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 2)

            Divider()

            // Tab content
            switch selectedTab {
            case .general:
                GeneralTab()
            case .integrations:
                IntegrationsTab(hookDetector: hookDetector)
            case .about:
                AboutTab(manager: manager)
            }
        }
        .frame(width: 400, height: 540)
        .onAppear {
            if hookDetector.isSessionEndHookMissing {
                selectedTab = .integrations
            }
        }
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("scanInterval") private var scanInterval = 10.0
    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }

            Section("Monitoring") {
                Picker("Scan interval", selection: $scanInterval) {
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
                Toggle("Show estimated cost per session", isOn: $costTrackingEnabled)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Data") {
                Text("Finished sessions older than 24 hours are automatically removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Integrations Tab

private struct IntegrationsTab: View {
    @ObservedObject var hookDetector: HookDetector
    @AppStorage("apiPort") private var apiPort = 19199

    var body: some View {
        Form {
            if hookDetector.isSessionEndHookMissing {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SessionEnd hook not configured")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Copy the hook config below and paste into ~/.claude/settings.json for session close detection.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("API Server") {
                HStack {
                    Text("Port")
                    TextField("Port", value: $apiPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiPort) { _, newValue in
                            if newValue < 1024 { apiPort = 1024 }
                            if newValue > 65535 { apiPort = 65535 }
                        }
                }
                Text("Runs on localhost:\(apiPort) only. Restart app after changing port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude Code Hooks") {
                Text("Add to ~/.claude/settings.json for session tracking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Copy Hook Config") {
                    copyHookConfig()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyHookConfig() {
        let config = """
{
  "hooks": {
    "PostToolUse": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event tool-use'"}],
    "Stop": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event stopped'"}],
    "SubagentStop": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event tool-use'"}],
    "Notification": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event needs-input'"}],
    "SessionEnd": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event session-end'"}]
  }
}
"""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
}

// MARK: - About Tab

private struct AboutTab: View {
    @ObservedObject var manager: SessionManager
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @AppStorage("checkForUpdatesAutomatically") private var autoCheckUpdates = true
    @AppStorage("apiPort") private var apiPort = 19199

    var body: some View {
        Form {
            Section {
                VStack(spacing: 4) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .padding(.bottom, 4)
                    Text("AgentPing")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Version \(UpdateChecker.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Run 10 agents. Know which one needs you.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                HStack(spacing: 24) {
                    Spacer()
                    Link(destination: URL(string: "https://github.com/ericermerimen/agentping")!) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://ericermerimen.github.io/agentping/")!) {
                        Label("Website", systemImage: "globe")
                    }
                    Link(destination: URL(string: "https://github.com/ericermerimen/agentping/blob/main/LICENSE")!) {
                        Label("License", systemImage: "doc.text")
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Updates") {
                Toggle("Check automatically on launch", isOn: $autoCheckUpdates)

                HStack {
                    if let error = updateChecker.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else if updateChecker.hasUpdate, let latest = updateChecker.latestVersion {
                        Text("v\(latest) available")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if updateChecker.latestVersion != nil {
                        Text("Up to date")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button {
                        updateChecker.check()
                    } label: {
                        if updateChecker.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                            Text("Checking...")
                        } else {
                            Text("Check Now")
                        }
                    }
                    .disabled(updateChecker.isChecking)
                }

                if updateChecker.hasUpdate, let url = updateChecker.updateURL {
                    HStack {
                        Text("Update via Homebrew:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                "brew update && brew upgrade agentping && sudo cp -pR $(brew --prefix)/opt/agentping/AgentPing.app /Applications/",
                                forType: .string
                            )
                        }
                        .font(.caption)
                    }
                    Button("View Release on GitHub") {
                        NSWorkspace.shared.open(url)
                    }
                    .font(.caption)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Spacer()
                    Button("Copy Debug Info") {
                        copyDebugInfo()
                    }
                    Button("Open Data Folder") {
                        let path = ("~/.agentping" as NSString).expandingTildeInPath
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    Spacer()
                }
            }

            Section {
                Text("\u{00A9} 2026 Eric Ermerimen. PolyForm Noncommercial 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
    }

    private func copyDebugInfo() {
        let activeSessions = manager.sessions.filter {
            $0.status == .running || $0.status == .needsInput || $0.status == .idle
        }.count
        let scanner = ProcessScanner()
        let claudeProcesses = scanner.scan().count
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let info = """
AgentPing v\(UpdateChecker.currentVersion)
macOS \(osVersion)
API port: \(apiPort)
Active sessions: \(activeSessions)
Claude processes: \(claudeProcesses)
"""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}
