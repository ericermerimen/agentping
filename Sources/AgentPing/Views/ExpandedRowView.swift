import SwiftUI
import AgentPingCore

struct ExpandedRowView: View {
    let session: Session
    let costTrackingEnabled: Bool
    var onTap: (() -> Void)?
    var onReviewed: (() -> Void)?

    @State private var now = Date()
    @State private var isHovered = false
    @State private var showHover = false
    @State private var hoverTask: DispatchWorkItem?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar for attention rows
            if session.isAttention {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accentColor)
                    .frame(width: 2)
                    .padding(.vertical, 4)
                    .padding(.trailing, 10)
            } else {
                Spacer()
                    .frame(width: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if session.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }

                    Text(session.projectName)
                        .font(.system(size: 13, weight: session.isAttention ? .medium : .regular))
                        .foregroundStyle(session.isAttention ? .primary : .secondary)
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

                if let sub = session.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Context window progress bar
                if let pct = session.contextPercent, pct > 0 {
                    contextBar(percent: pct)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
            if costTrackingEnabled, let cost = session.costUsd, cost > 0 {
                Text(String(format: "~$%.2f", cost))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.quaternary)
            }

            if session.status == .needsInput {
                Text("Reply")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.systemOrange))
            } else if session.isFreshIdle {
                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.systemTeal))
            } else if session.status == .idle {
                Text(idleElapsed)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else if session.status == .error {
                Text("Error")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(.systemRed))
            } else if session.status == .running {
                Text("Running")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(.systemGreen).opacity(0.8))
            } else {
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            } // end VStack trailing
            .frame(width: 60, alignment: .trailing)
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
            if session.isFreshIdle { onReviewed?() }
            onTap?()
        }
        .popover(isPresented: $showHover, arrowEdge: .trailing) {
            SessionHoverView(session: session)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .onReceive(timer) { now = $0 }
    }

    private var accessibilityDescription: String {
        var parts = [session.projectName]
        if session.status == .needsInput { parts.append("needs input") }
        else if session.isFreshIdle { parts.append("ready for review") }
        else if session.status == .error { parts.append("error") }
        else if session.status == .running { parts.append("running") }
        else { parts.append(statusLabel.lowercased()) }
        if let pct = session.contextPercent, pct > 0 {
            parts.append("context \(Int(pct * 100))%")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Background

    private var rowBackground: some View {
        Group {
            if session.status == .needsInput {
                Color(.systemOrange).opacity(isHovered ? 0.12 : 0.06)
            } else if session.status == .error {
                Color(.systemRed).opacity(isHovered ? 0.12 : 0.06)
            } else if session.isFreshIdle {
                Color(.systemTeal).opacity(isHovered ? 0.12 : 0.06)
            } else {
                Color.primary.opacity(isHovered ? 0.05 : 0)
            }
        }
    }

    // MARK: - Computed

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
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.top, 2)
    }

    private var accentColor: Color {
        if session.isFreshIdle { return Color(.systemTeal) }
        switch session.status {
        case .error: return Color(.systemRed)
        default:     return Color(.systemOrange)
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .done:  return "Done"
        case .idle:  return "Idle"
        default:     return ""
        }
    }

    private var idleElapsed: String {
        session.idleElapsed(now: now)
    }
}
