import SwiftUI

public enum MainSection: Hashable {
    case dashboard
    case profile(String)
    case doctor
}

public struct MainWindowView: View {
    let model: AppModel
    let usage: UsageStore
    @State private var selection: MainSection? = .dashboard
    @State private var showingAddSheet = false

    public init(model: AppModel, usage: UsageStore) {
        self.model = model
        self.usage = usage
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
                    .tag(MainSection.dashboard)

                Section("Profiles") {
                    ForEach(model.snapshots) { snapshot in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(dotColor(snapshot.health))
                                .frame(width: 7, height: 7)
                            Text(snapshot.name)
                            if snapshot.isActive {
                                Spacer()
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(MainSection.profile(snapshot.name))
                    }
                }

                Label("Doctor", systemImage: "stethoscope")
                    .badge(model.totalIssueCount)
                    .tag(MainSection.doctor)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) {
                if model.canStartFlows {
                    HStack {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Add Profile", systemImage: "plus")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(8)
                    .sheet(isPresented: $showingAddSheet) {
                        AddProfileSheet(model: model, isPresented: $showingAddSheet)
                    }
                }
            }
        } detail: {
            switch selection {
            case .dashboard, nil:
                DashboardView(model: model, usage: usage)
            case .profile(let name):
                if let snapshot = model.snapshots.first(where: { $0.name == name }) {
                    ProfileDetailView(snapshot: snapshot, model: model, usage: usage, selection: $selection)
                } else {
                    ContentUnavailableView("Profile not found", systemImage: "person.crop.circle.badge.questionmark")
                }
            case .doctor:
                DoctorView(model: model)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .toolbar {
            Button {
                model.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            .help("Settings")
        }
    }

    private func dotColor(_ health: HealthStatus) -> Color {
        switch health {
        case .healthy: .green
        case .issues: .red
        case .unknown: .gray
        }
    }
}
