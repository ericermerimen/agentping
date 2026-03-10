import SwiftUI
import AppKit
import ServiceManagement

struct PreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("scanInterval") private var scanInterval = 10.0
    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false

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
            }

            Section("Hooks") {
                Text("Add these hooks to ~/.claude/settings.json to enable rich session tracking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Copy Hook Config to Clipboard") {
                    copyHookConfig()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 360)
    }

    private func copyHookConfig() {
        let config = """
        {
          "hooks": {
            "PostToolUse": [{"command": "agentshub report --session $CLAUDE_SESSION_ID --event tool-use"}],
            "Stop": [{"command": "agentshub report --session $CLAUDE_SESSION_ID --event stopped"}],
            "Notification": [{"command": "agentshub report --session $CLAUDE_SESSION_ID --event needs-input"}]
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }
}
