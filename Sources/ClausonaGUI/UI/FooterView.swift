import SwiftUI

struct FooterView: View {
    let model: AppModel
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(updatedText)
                        .font(.system(size: 11))
                        .foregroundStyle(model.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button {
                    Task { await model.refreshUsage() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                Spacer()
            }

            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Button("Open Clausona…") { model.openMainWindow() }
                    .controlSize(.small)
                Spacer()
                if model.canStartFlows {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .controlSize(.small)
                    .help("Add profile (continues in your terminal)")
                }
                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .controlSize(.small)
                .keyboardShortcut(",")
                .help("Settings")
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
            .sheet(isPresented: $showingAddSheet) {
                AddProfileSheet(model: model, isPresented: $showingAddSheet)
            }

            if !model.cliAvailable {
                Text("clausona CLI not found — switching and repair disabled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var updatedText: String {
        guard let lastUpdated = model.lastUpdated else { return "Not updated yet" }
        let seconds = Int(Date().timeIntervalSince(lastUpdated))
        return "Updated \(Formatting.updatedAgo(seconds: max(0, seconds)))"
    }
}
