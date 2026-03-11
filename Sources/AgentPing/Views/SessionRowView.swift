import SwiftUI
import AgentPingCore

struct SessionRowView: View {
    let session: Session
    var onTap: (() -> Void)?

    @AppStorage("costTrackingEnabled") private var costTrackingEnabled = false
    @State private var now = Date()
    @State private var isHovered = false
    @State private var showHover = false
    @State private var hoverTask: DispatchWorkItem?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isAttention: Bool {
        session.status == .needsInput || session.status == .error
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar for attention rows
            if isAttention {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accentColor)
                    .frame(width: 2)
                    .padding(.vertical, 4)
                    .padding(.trailing, 10)
            } else {
                // Dot for running/idle
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if session.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }

                    Text(projectName)
                        .font(.system(size: 13, weight: isAttention ? .medium : .regular))
                        .foregroundStyle(isAttention ? .primary : .secondary)
                        .lineLimit(1)

                    if let app = session.app, !app.isEmpty {
                        Text(app)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                // Context window progress bar
                if let pct = session.contextPercent, pct > 0 {
                    contextBar(percent: pct)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
            if costTrackingEnabled, let cost = session.costUsd, cost > 0 {
                Text(String(format: "$%.2f", cost))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.quaternary)
            }

            if session.status == .needsInput {
                Text("Waiting")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.systemOrange))
            } else if session.status == .idle {
                Text(idleElapsed)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else if session.status == .error {
                Text("Error")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.systemRed))
            } else if session.status == .running {
                Text(elapsedTime)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            } // end VStack trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            hoverTask?.cancel()
            if hovering {
                let task = DispatchWorkItem { showHover = true }
                hoverTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
            } else {
                showHover = false
            }
        }
        .onTapGesture {
            hoverTask?.cancel()
            showHover = false
            onTap?()
        }
        .popover(isPresented: $showHover, arrowEdge: .trailing) {
            SessionHoverView(session: session)
        }
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Background

    private var rowBackground: some View {
        Group {
            if session.status == .needsInput {
                Color(.systemOrange).opacity(isHovered ? 0.12 : 0.06)
            } else if session.status == .error {
                Color(.systemRed).opacity(isHovered ? 0.12 : 0.06)
            } else {
                Color.primary.opacity(isHovered ? 0.05 : 0)
            }
        }
    }

    // MARK: - Computed

    private var isHomeCwd: Bool {
        guard let cwd = session.cwd else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd == home || cwd == home + "/"
    }

    private var projectName: String {
        if let cwd = session.cwd, !cwd.isEmpty, !isHomeCwd {
            let last = URL(fileURLWithPath: cwd).lastPathComponent
            if !last.isEmpty { return last }
        }
        // If cwd is home dir, use task description as name
        if let task = session.taskDescription, !task.isEmpty {
            return task
        }
        return session.name ?? "Unnamed"
    }

    /// Subtitle: show task if project name is from cwd, show path if name is from task
    private var subtitle: String? {
        if isHomeCwd {
            return "~"
        }
        if let task = session.taskDescription, !task.isEmpty, !isHomeCwd {
            return task
        }
        return displayPath.isEmpty ? nil : displayPath
    }

    private var displayPath: String {
        guard let cwd = session.cwd, !cwd.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
    }

    private func contextBar(percent: Double) -> some View {
        HStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(contextBarColor(percent))
                        .frame(width: geo.size.width * min(percent, 1.0), height: 3)
                }
            }
            .frame(height: 3)

            Text("\(Int(percent * 100))%")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.quaternary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.top, 2)
    }

    private func contextBarColor(_ pct: Double) -> Color {
        if pct > 0.85 { return Color(.systemRed).opacity(0.8) }
        if pct > 0.65 { return Color(.systemOrange).opacity(0.7) }
        return Color(.systemGreen).opacity(0.5)
    }

    private var accentColor: Color {
        switch session.status {
        case .error: return Color(.systemRed)
        case .idle:  return Color(.systemBlue)
        default:     return Color(.systemOrange)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running:     return Color(.systemGreen).opacity(0.7)
        case .idle:        return Color(.systemYellow).opacity(0.6)
        case .done:        return Color(.systemGray)
        case .unavailable: return Color(.systemGray)
        default:           return .clear
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .done:  return "Done"
        case .idle:  return "Idle"
        default:     return ""
        }
    }

    private var elapsedTime: String {
        let total = max(0, Int(now.timeIntervalSince(session.lastEventAt)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private var idleElapsed: String {
        let total = max(0, Int(now.timeIntervalSince(session.lastEventAt)))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 {
            return "idle \(h)h"
        } else if m > 0 {
            return "idle \(m)m"
        } else {
            return "idle"
        }
    }
}
