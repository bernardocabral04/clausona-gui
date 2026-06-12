import SwiftUI

public struct MainWindowView: View {
    let model: AppModel
    let usage: UsageStore

    public init(model: AppModel, usage: UsageStore) {
        self.model = model
        self.usage = usage
    }

    public var body: some View {
        Text("Clausona")   // replaced in Task 10
            .frame(minWidth: 400, minHeight: 300)
    }
}
