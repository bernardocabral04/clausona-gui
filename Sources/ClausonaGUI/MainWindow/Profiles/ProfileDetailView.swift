import SwiftUI

struct ProfileDetailView: View {
    let snapshot: ProfileSnapshot
    let model: AppModel
    let usage: UsageStore
    @Binding var selection: MainSection?

    var body: some View {
        Text(snapshot.name)   // Task 12
    }
}
