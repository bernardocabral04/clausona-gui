import SwiftUI

struct AddProfileSheet: View {
    let model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""

    private var isValid: Bool { ProfileName.isValid(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add profile")
                .font(.headline)
            TextField("profile-name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { submit() }
            Text("Lowercase letters, digits and dashes. The setup continues in your terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !name.isEmpty && !isValid {
                Text("Invalid name — use a-z, 0-9 and dashes only.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(16)
    }

    private func submit() {
        guard isValid else { return }
        isPresented = false
        model.startFlow(.add(name: name))
    }
}
