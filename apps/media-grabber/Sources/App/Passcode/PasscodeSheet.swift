import SwiftUI

struct PasscodeSheet: View {
    let appModel: AppModel
    @State private var text = ""

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var message: String {
        if appModel.passcodeNeeded?.wasRejected == true {
            "That passcode didn't work. Check it and try again."
        } else {
            "This recording is protected. Enter the passcode its owner gave you."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("Enter passcode")
                .font(.headline)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Passcode", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    appModel.cancelPasscodePrompt()
                }
                .keyboardShortcut(.cancelAction)
                Button("Continue", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(Spacing.s4)
        .frame(width: 380)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        let entered = text
        Task { await appModel.submitPasscode(entered) }
    }
}
