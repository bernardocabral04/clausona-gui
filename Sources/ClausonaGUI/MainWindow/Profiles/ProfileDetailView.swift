import SwiftUI

struct ProfileDetailView: View {
    let snapshot: ProfileSnapshot
    let model: AppModel
    let usage: UsageStore
    @Binding var selection: MainSection?

    private var profile: Profile? {
        model.profilesFile?.profiles.first { $0.name == snapshot.name }
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Profile", value: snapshot.name)
                if let email = profile?.email { LabeledContent("Email", value: email) }
                if let org = profile?.orgName { LabeledContent("Organization", value: org) }
                if let dir = profile?.configDir {
                    LabeledContent("Config directory") {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir)
                        } label: {
                            HStack(spacing: 4) {
                                Text(dir)
                                Image(systemName: "arrow.up.forward.square")
                            }
                        }
                        .buttonStyle(.link)
                        .help("Reveal in Finder")
                    }
                }
                LabeledContent("Primary", value: profile?.isPrimary == true ? "Yes" : "No")
            }

            Section("Credentials") {
                LabeledContent("Status", value: credentialText)
            }

            Section("Rate limits") {
                limitsRow
            }

            Section("Health") {
                HStack {
                    Text(healthText)
                    Spacer()
                    Button("View in Doctor") { selection = .doctor }
                        .buttonStyle(.link)
                }
            }

            Section("Usage — \(usage.range.rawValue)") {
                let totals = usage.totalsByProfile()[snapshot.name] ?? .zero
                LabeledContent("Cost", value: Formatting.cost(totals.cost))
                LabeledContent("Input tokens", value: Formatting.tokens(totals.inputTokens))
                LabeledContent("Output tokens", value: Formatting.tokens(totals.outputTokens))
            }

            if model.canStartFlows {
                Section("Actions") {
                    LabeledContent("Re-authenticate") {
                        Button("clausona login \(snapshot.name)") {
                            model.startFlow(.login(name: snapshot.name))
                        }
                    }
                    LabeledContent("Configure") {
                        Button("clausona config \(snapshot.name)") {
                            model.startFlow(.config(name: snapshot.name))
                        }
                    }
                    LabeledContent("Remove") {
                        Button(role: .destructive) {
                            model.startFlow(.remove(name: snapshot.name))
                        } label: {
                            Text("clausona remove \(snapshot.name)…")
                        }
                        .help("Opens clausona's removal flow in your terminal — confirmation happens there")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(snapshot.name)
    }

    private var credentialText: String {
        switch snapshot.credential {
        case .unknown: "Not checked yet"
        case .valid(let until): "Valid until \(until.formatted(date: .abbreviated, time: .shortened))"
        case .expired: "Expired — run clausona login \(snapshot.name)"
        case .missing: "No credentials found"
        }
    }

    private var healthText: String {
        switch snapshot.health {
        case .healthy: "Healthy"
        case .issues(let issues): "\(issues.count) issue\(issues.count == 1 ? "" : "s")"
        case .unknown: "Unknown"
        }
    }

    @ViewBuilder private var limitsRow: some View {
        switch snapshot.usage {
        case .loading:
            Text("Loading…").foregroundStyle(.secondary)
        case .ok(let report):
            windowLine("5-hour window", report.fiveHour)
            windowLine("7-day window", report.sevenDay)
        case .error(let message, let lastGood):
            if let lastGood {
                windowLine("5-hour window", lastGood.fiveHour)
                windowLine("7-day window", lastGood.sevenDay)
            }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func windowLine(_ label: String, _ window: UsageWindow?) -> some View {
        LabeledContent(label) {
            if let window {
                Text("\(window.utilization)%" + suffix(window.resetsAt)).monospacedDigit()
            } else {
                Text("—")
            }
        }
    }

    private func suffix(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        return "  (resets in \(Formatting.duration(seconds: Int(resetsAt.timeIntervalSinceNow))))"
    }
}
