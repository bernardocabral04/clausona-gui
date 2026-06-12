import SwiftUI

struct ToastView: View {
    let model: AppModel

    var body: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.92), in: Capsule())
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast)
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    model.toast = nil
                }
        }
    }
}
