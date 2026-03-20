import SwiftUI
import AgentPingCore

struct SessionHoverView: View {
    let session: Session
    @EnvironmentObject private var displayPrefs: DisplayPreferences
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + Status
            HStack(spacing: 6) {
                Text(session.name ?? "Unnamed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let model = modelLabel {
                    Text(model)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            // Task description
            if let task = session.taskDescription, !task.isEmpty {
                Text(task)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Context bar
            if let pct = session.contextPercent, pct > 0 {
                HStack(spacing: 6) {
                    Text("Context")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(contextBarColor(pct))
                                .frame(width: geo.size.width * min(pct, 1.0), height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Divider().opacity(0.5)

            // Duration + last activity
            HStack {
                Text("Started")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(relativeTime(from: session.startedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text("Last activity")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(relativeTime(from: session.lastEventAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            // Cost
            if displayPrefs.costTrackingEnabled, let cost = session.costUsd, cost > 0 {
                HStack {
                    Text("Cost (est.)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "~$%.2f", cost))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // cwd
            if let cwd = session.cwd, !cwd.isEmpty {
                HStack {
                    Text("Path")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(session.displayPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Session ID
            HStack {
                Text("Session")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(session.id.prefix(12) + "...")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onReceive(timer) { now = $0 }
    }

    private var modelLabel: String? {
        let parts = [session.provider, session.model].compactMap { $0 }
            .filter { !$0.hasPrefix("<") && $0 != "Unknown" }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var statusLabel: String {
        if session.isFreshIdle { return "Ready" }
        switch session.status {
        case .running:     return "Running"
        case .needsInput:  return "Needs Input"
        case .idle:        return "Idle"
        case .error:       return "Error"
        case .done:        return "Done"
        case .unavailable: return "Unavailable"
        }
    }

    private var statusColor: Color {
        if session.isFreshIdle { return Color(.systemTeal) }
        switch session.status {
        case .running:    return Color(.systemGreen)
        case .needsInput: return Color(.systemOrange)
        case .idle:       return Color(.systemBlue)
        case .error:      return Color(.systemRed)
        case .done:       return Color(.systemGray)
        case .unavailable: return Color(.systemGray)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}
