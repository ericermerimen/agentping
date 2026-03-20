import SwiftUI
import AgentPingCore

struct CompactRowView: View {
    let session: Session
    var onTap: (() -> Void)?
    var onReviewed: (() -> Void)?

    @State private var now = Date()
    @State private var isHovered = false
    @State private var showHover = false
    @State private var hoverTask: DispatchWorkItem?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            if session.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.quaternary)
            }

            Text(session.projectName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            statusView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isHovered ? 0.04 : 0))
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
        .accessibilityLabel("\(session.projectName), \(statusText)")
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private var statusView: some View {
        if session.status == .running {
            Text("Running")
                .font(.system(size: 11))
                .foregroundStyle(Color(.systemGreen).opacity(0.8))
        } else if session.status == .error {
            Text("Error")
                .font(.system(size: 11))
                .foregroundStyle(Color(.systemRed).opacity(0.8))
        } else if session.status == .idle {
            Text(idleElapsed)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
        } else if session.status == .done {
            Text("Done")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            Text("Unavailable")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var statusText: String {
        if session.status == .running { return "running" }
        if session.status == .error { return "error" }
        if session.status == .idle { return idleElapsed }
        if session.status == .done { return "done" }
        return "unavailable"
    }

    private var idleElapsed: String {
        session.idleElapsed(now: now)
    }
}
