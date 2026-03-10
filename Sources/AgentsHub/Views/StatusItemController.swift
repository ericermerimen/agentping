import AppKit
import SwiftUI
import AgentsHubCore
import Combine

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    init(manager: SessionManager) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(manager: manager)
        )

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.grid.2x2", accessibilityDescription: "AgentsHub")
            button.action = #selector(togglePopover)
            button.target = self
        }

        manager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateIcon(sessions: sessions)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(sessions: [Session]) {
        guard let button = statusItem.button else { return }

        let active = sessions.filter { [.running, .needsInput, .idle].contains($0.status) }
        let needsInput = sessions.contains(where: { $0.status == .needsInput })

        let title = active.isEmpty ? "" : " \(active.count)"
        button.title = title

        // Use filled icon when sessions need input
        let symbolName = needsInput ? "circle.grid.2x2.fill" : "circle.grid.2x2"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AgentsHub")

        // Red badge dot overlay via attributed title
        if needsInput {
            let attr = NSMutableAttributedString(string: title)
            attr.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: attr.length))
            button.attributedTitle = attr
        } else {
            button.attributedTitle = NSAttributedString(string: title)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
