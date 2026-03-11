import SwiftUI
import AppKit
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("scanInterval") private var scanInterval = 10.0
    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false
    @AppStorage("apiPort") private var apiPort = 19199
    @StateObject private var updateChecker = UpdateChecker()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }

                Picker("Scan interval", selection: $scanInterval) {
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Text("Per-session notifications can be toggled from the session context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Toggle("Show cost per session", isOn: $costTrackingEnabled)
                Text("Finished sessions older than 24 hours are automatically removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API") {
                HStack {
                    Text("Port")
                    TextField("Port", value: $apiPort, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiPort) { _, newValue in
                            // Clamp to valid port range
                            if newValue < 1024 { apiPort = 1024 }
                            if newValue > 65535 { apiPort = 65535 }
                        }
                }
                Text("API server runs on localhost:\(apiPort). Restart app after changing port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hooks") {
                Text("Add these hooks to ~/.claude/settings.json to enable rich session tracking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Copy Hook Config to Clipboard") {
                    copyHookConfig()
                }
            }

            Section("Updates") {
                HStack {
                    Text("Current version")
                    Spacer()
                    Text(UpdateChecker.currentVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        updateChecker.check()
                    } label: {
                        if updateChecker.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                            Text("Checking...")
                        } else {
                            Text("Check for Updates")
                        }
                    }
                    .disabled(updateChecker.isChecking)

                    Spacer()

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
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 520)
    }

    private func copyHookConfig() {
        let config = """
        {
          "hooks": {
            "PostToolUse": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event tool-use'"}],
            "Stop": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event stopped'"}],
            "Notification": [{"command": "bash -c 'agentping report --session $(jq -r .session_id) --event needs-input'"}]
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
}
