import SwiftUI
import AgentPingCore

enum SessionTab: String, CaseIterable {
    case active = "Active"
    case history = "History"
}

struct PopoverView: View {
    @ObservedObject var manager: SessionManager
    @ObservedObject var hookDetector: HookDetector
    @EnvironmentObject var displayPrefs: DisplayPreferences
    var openPreferences: (() -> Void)?
    var dismissPopover: (() -> Void)?

    @State private var selectedTab: SessionTab = .active
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var now = Date()

    private var attentionCount: Int {
        manager.sessions.filter { $0.status == .needsInput || $0.status == .error || $0.isFreshIdle }.count
    }

    private var syncTooltip: String {
        guard let lastSync = manager.lastSyncAt else { return "Sync sessions" }
        let seconds = Int(now.timeIntervalSince(lastSync))
        if seconds < 5 { return "Synced just now" }
        if seconds < 60 { return "Synced \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes == 1 { return "Synced 1 min ago" }
        return "Synced \(minutes) min ago"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if hookDetector.isSessionEndHookMissing {
                hookWarningBanner
            }

            Divider().opacity(0.5)

            if showSearch {
                searchBar
                Divider().opacity(0.3)
            }

            tabBar
            Divider().opacity(0.3)
            sessionList

            Divider().opacity(0.3)
            footer
        }
        .frame(width: 340, height: 460)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("AgentPing")
                .font(.system(size: 13, weight: .semibold))

            Text(UpdateChecker.currentVersion)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showSearch.toggle()
                    if !showSearch { searchText = "" }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(showSearch ? .primary : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Search sessions")

            Button { manager.sync() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(syncTooltip)

            Button { openPreferences?() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Hook Warning

    private var hookWarningBanner: some View {
        Button {
            openPreferences?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 10))
                Text("SessionEnd hook not configured")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Fix")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.06))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            TextField("Filter sessions...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            tabButton(.active)
            tabButton(.history)
            Spacer()

            if selectedTab == .history && !manager.historySessions.isEmpty {
                Button {
                    manager.clearHistory()
                } label: {
                    Text("Clear")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all history")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func tabButton(_ tab: SessionTab) -> some View {
        let isSelected = selectedTab == tab

        let badgeCount: Int = {
            if tab == .active { return attentionCount }
            if tab == .history { return manager.historySessions.count }
            return 0
        }()

        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { selectedTab = tab }
        } label: {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tab == .active && attentionCount > 0 ? Color(.systemTeal) : Color.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (tab == .active && attentionCount > 0
                                ? Color(.systemTeal).opacity(0.15)
                                : Color.primary.opacity(0.06)),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session list

    private func filteredSessions(_ sessions: [Session]) -> [Session] {
        guard !searchText.isEmpty else { return sessions }
        let query = searchText.lowercased()
        return sessions.filter { s in
            (s.name ?? "").lowercased().contains(query) ||
            (s.cwd ?? "").lowercased().contains(query) ||
            (s.taskDescription ?? "").lowercased().contains(query) ||
            (s.app ?? "").lowercased().contains(query)
        }
    }

    private func sortPriority(_ session: Session) -> Int {
        if session.isFreshIdle { return 2 } // between error(1) and running(3)
        return session.status.sortPriority
    }

    /// Group sessions by project directory, with pinned sessions first
    private func groupedActiveSessions() -> [(project: String, sessions: [Session])] {
        let sorted = manager.activeSessions.sorted { a, b in
            // Pinned first, then by status priority
            if a.pinned != b.pinned { return a.pinned }
            return sortPriority(a) < sortPriority(b)
        }

        let filtered = filteredSessions(sorted)

        // Group by project (last path component of cwd)
        var groups: [(String, [Session])] = []
        var seen = [String: Int]()

        for session in filtered {
            let project = projectKey(for: session)
            if let idx = seen[project] {
                groups[idx].1.append(session)
            } else {
                seen[project] = groups.count
                groups.append((project, [session]))
            }
        }

        return groups.map { (project: $0.0, sessions: $0.1) }
    }

    private func projectKey(for session: Session) -> String {
        guard let cwd = session.cwd, !cwd.isEmpty else { return "Other" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd == home || cwd == home + "/" { return "Home" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if selectedTab == .active {
                    activeSessionList
                } else {
                    historySessionList
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var activeSessionList: some View {
        let groups = groupedActiveSessions()

        if groups.isEmpty {
            emptyState
        } else if groups.count == 1 {
            // Single project -- no need for group headers
            ForEach(groups[0].sessions) { session in
                sessionRow(session)
            }
        } else {
            ForEach(groups, id: \.project) { group in
                projectHeader(group.project, count: group.sessions.count)
                ForEach(group.sessions) { session in
                    sessionRow(session)
                }
            }
        }
    }

    @ViewBuilder
    private var historySessionList: some View {
        let sessions = filteredSessions(manager.historySessions)

        if sessions.isEmpty {
            emptyState
        } else {
            ForEach(sessions) { session in
                historyRow(session)
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(spacing: 0) {
            if session.isAttention {
                ExpandedRowView(
                    session: session,
                    costTrackingEnabled: displayPrefs.costTrackingEnabled,
                    onTap: { jumpToWindow(session: session) },
                    onReviewed: { manager.markReviewed(id: session.id) }
                )
            } else {
                CompactRowView(
                    session: session,
                    onTap: { jumpToWindow(session: session) },
                    onReviewed: { manager.markReviewed(id: session.id) }
                )
            }
        }
        .contextMenu { sessionContextMenu(session: session) }
    }

    private func historyRow(_ session: Session) -> some View {
        VStack(spacing: 0) {
            CompactRowView(
                session: session,
                onTap: { jumpToWindow(session: session) },
                onReviewed: { manager.markReviewed(id: session.id) }
            )
        }
        .contextMenu { sessionContextMenu(session: session) }
    }

    private func projectHeader(_ name: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            Text("\(count)")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func sessionContextMenu(session: Session) -> some View {
        Button("Jump to Window") {
            jumpToWindow(session: session)
        }

        Button(session.pinned ? "Unpin" : "Pin to Top") {
            manager.togglePin(id: session.id)
        }

        Divider()

        if let cwd = session.cwd {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cwd, forType: .string)
            }

            Button("Open in Terminal") {
                openTerminal(at: cwd)
            }
        }

        Button("Copy Session ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.id, forType: .string)
        }

        if let transcriptPath = session.transcriptPath {
            Button("Open Transcript") {
                NSWorkspace.shared.open(URL(fileURLWithPath: transcriptPath))
            }
        }

        Divider()

        if session.isFreshIdle {
            Button("Mark as Reviewed") {
                manager.markReviewed(id: session.id)
            }
        }

        if session.status == .running || session.status == .needsInput || session.status == .idle {
            Button("Mark as Done") {
                var updated = session
                updated.status = .done
                manager.updateSession(updated)
            }
        }

        Button("Delete Session") {
            manager.deleteSession(id: session.id)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(syncTooltip)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            Spacer()

            if displayPrefs.costTrackingEnabled && manager.totalCost > 0 {
                Text("Total cost (est.)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(String(format: "~$%.2f", manager.totalCost))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("\u{2303}\u{2325}A")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .help("Toggle with Ctrl+Option+A")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            if !searchText.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .thin))
                    .foregroundStyle(.quaternary)
                Text("No matching sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            } else {
                Image(systemName: selectedTab == .active ? "terminal" : "clock")
                    .font(.system(size: 20, weight: .thin))
                    .foregroundStyle(.quaternary)
                Text(selectedTab == .active ? "No active sessions" : "No history")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - Actions

    private func jumpToWindow(session: Session) {
        dismissPopover?()
        DispatchQueue.global(qos: .userInteractive).async {
            let jumper = WindowJumper()
            let success = jumper.jumpTo(session: session)
            if !success {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }

    private func openTerminal(at path: String) {
        // Validate the path exists and is a directory before executing
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        // Use Process with open(1) to avoid all string interpolation injection risks.
        // open -a Terminal <dir> opens a new Terminal window cd'd to the directory.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }
}

// MARK: - Sort priority for status

extension SessionStatus {
    var sortPriority: Int {
        switch self {
        case .needsInput:  return 0
        case .error:       return 1
        // freshIdle = 2 (handled in PopoverView.sortPriority)
        case .running:     return 3
        case .idle:        return 4
        case .done:        return 5
        case .unavailable: return 6
        }
    }
}
