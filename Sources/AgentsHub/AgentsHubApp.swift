import SwiftUI
import AgentsHubCore

@main
struct AgentsHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusItemController?
    let manager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApplication.shared.setActivationPolicy(.accessory)

        controller = StatusItemController(manager: manager)
        manager.reload()
        startPeriodicScan()
    }

    private func startPeriodicScan() {
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.manager.reload()
        }
    }
}
