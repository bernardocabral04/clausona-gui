import SwiftUI

struct ProfileRowView: View {
    let snapshot: ProfileSnapshot
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 7))
                .foregroundStyle(.primary)
                .opacity(snapshot.isActive ? 1 : 0)
                .frame(width: 10)

            healthDot

            Text(snapshot.name)
                .font(.system(size: 12, weight: snapshot.isActive ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 8)

            usageContent

            actionButton
        }
        // Constant height (fits the hover-revealed buttons) so rows don't
        // grow on hover and the popover doesn't twitch.
        .frame(height: 20)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(hovering ? Color.primary.opacity(0.07) : .clear))
        .onHover { hovering = $0 }
    }

    private var healthDot: some View {
        Group {
            if snapshot.isRepairing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 12, height: 12)
        .help(healthTooltip)
    }

    private var dotColor: Color {
        switch snapshot.health {
        case .healthy: .green
        case .issues: .red
        case .unknown: .gray
        }
    }

    private var healthTooltip: String {
        switch snapshot.health {
        case .healthy: "Healthy"
        case .issues(let issues): issues.joined(separator: "\n")
        case .unknown: "Health unknown"
        }
    }

    @ViewBuilder private var usageContent: some View {
        switch snapshot.usage {
        case .loading:
            Text("…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        case .ok(let report):
            segments(report)
        case .error(let message, let lastGood):
            if let lastGood {
                segments(lastGood)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func segments(_ report: UsageReport) -> some View {
        HStack(spacing: 10) {
            segment(label: "5h", window: report.fiveHour)
            segment(label: "7d", window: report.sevenDay)
        }
    }

    private func segment(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            if let window {
                Text("\(window.utilization)%")
                    .fontWeight(.medium)
                    .foregroundStyle(percentColor(window.utilization))
                Text(resetText(window.resetsAt))
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func resetText(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        return "(\(Formatting.duration(seconds: Int(resetsAt.timeIntervalSinceNow))))"
    }

    private func percentColor(_ percent: Int) -> Color {
        switch UsageSeverity(percent: percent) {
        case .normal: .green
        case .elevated: .orange
        case .critical: .red
        }
    }

    @ViewBuilder private var actionButton: some View {
        if hovering && model.cliAvailable {
            if case .issues = snapshot.health, !snapshot.isRepairing {
                Button("Repair") {
                    Task { await model.repair(snapshot.name) }
                }
                .controlSize(.small)
                .help("Runs `clausona repair \(snapshot.name)`")
            } else if needsLogin && model.canStartFlows {
                Button("Login") {
                    model.startFlow(.login(name: snapshot.name))
                }
                .controlSize(.small)
                .help("Re-authenticate in your terminal")
            } else if !snapshot.isActive {
                Button("Use") {
                    Task { await model.switchProfile(snapshot.name) }
                }
                .controlSize(.small)
                .help("Runs `clausona use \(snapshot.name)` — affects new terminals only")
            }
        }
    }

    private var needsLogin: Bool {
        if case .expired = snapshot.credential { return true }
        if case .missing = snapshot.credential { return true }
        return false
    }
}
