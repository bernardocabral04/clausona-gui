import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    init(settings: AppSettings, model: AppModel) {
        self._settings = Bindable(settings)
        self.model = model
    }

    var body: some View {
        Form {
            Section("Terminal for clausona flows") {
                Picker("Terminal", selection: $settings.terminal) {
                    ForEach(TerminalLauncher.TerminalChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .labelsHidden()
                if settings.terminal == .other {
                    LabeledContent("App") {
                        HStack {
                            Text(settings.otherTerminalPath.map { ($0 as NSString).lastPathComponent } ?? "None chosen")
                                .foregroundStyle(.secondary)
                            Button("Choose…") { chooseApp() }
                        }
                    }
                }
                if let warning = terminalWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Refresh") {
                Picker("Background refresh", selection: $settings.refreshMinutes) {
                    ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                        Text("Every \(minutes) minutes").tag(minutes)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }))
                LabeledContent("Hotkey", value: "⌃⌥⌘L (fixed)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshLaunchAtLogin() }
    }

    private var terminalWarning: String? {
        let path: String? = switch settings.terminal {
        case .terminal: nil
        case .warp: "/Applications/Warp.app"
        case .iterm: "/Applications/iTerm.app"
        case .other: settings.otherTerminalPath ?? "/nonexistent"
        }
        guard let path, !FileManager.default.fileExists(atPath: path) else { return nil }
        return "App not found — Terminal.app will be used instead"
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            settings.otherTerminalPath = url.path
        }
    }
}
