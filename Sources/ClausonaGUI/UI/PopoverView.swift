import SwiftUI

public struct PopoverView: View {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("clausona usage limits")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            switch model.setupState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            case .notSetUp:
                EmptyStateView(
                    title: "clausona is not set up",
                    hint: model.canStartFlows
                        ? "Initial setup discovers your Claude accounts in a terminal."
                        : "Run `clausona init` in a terminal to get started.",
                    actionTitle: model.canStartFlows ? "Set up clausona…" : nil,
                    action: model.canStartFlows ? { model.startFlow(.initialSetup) } : nil)
            case .ready:
                VStack(spacing: 1) {
                    ForEach(model.snapshots) { snapshot in
                        ProfileRowView(snapshot: snapshot, model: model)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
                .padding(.top, 10)
            FooterView(model: model)
        }
        .frame(width: 420)
        .overlay(alignment: .bottom) { ToastView(model: model) }
    }
}
