import SwiftUI

struct DoctorView: View {
    let model: AppModel
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.cliAvailable {
                    banner("clausona CLI not found — doctor and repair are unavailable.",
                           systemImage: "exclamationmark.triangle", color: .orange)
                }
                if let error = model.doctorError {
                    banner("Doctor run failed: \(error)", systemImage: "xmark.octagon", color: .red)
                }
                ForEach(model.snapshots) { snapshot in
                    profileSection(snapshot)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Doctor")
        .toolbar {
            Button {
                runDoctor()
            } label: {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run doctor again", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRunning || !model.cliAvailable)
        }
    }

    private func runDoctor() {
        isRunning = true
        Task {
            await model.refreshHealth()
            isRunning = false
        }
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func profileSection(_ snapshot: ProfileSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                switch snapshot.health {
                case .healthy:
                    Label("Healthy", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .unknown:
                    Label("Health unknown", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                case .issues(let issues):
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 12))
                    }
                    if model.cliAvailable {
                        Button {
                            Task { await model.repair(snapshot.name) }
                        } label: {
                            if snapshot.isRepairing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Repair", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .disabled(snapshot.isRepairing)
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack(spacing: 6) {
                Text(snapshot.name).font(.headline)
                if let email = snapshot.email {
                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
