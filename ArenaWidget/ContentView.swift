import ArenaKit
import SwiftUI
import WidgetKit

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Are.na Widget")
                    .font(.title2.weight(.semibold))
                Text("This app carries the widget and holds an optional access token.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Step(1, "Right-click the desktop and choose Edit Widgets.")
                Step(2, "Search for “Are.na”, pick a size, and drag it onto the desktop or into Notification Center.")
                Step(3, "Right-click the widget, choose Edit “Are.na Channel”, and paste a channel slug or URL.")
            }

            Divider()

            TokenSection()
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
    }
}

private struct Step: View {
    let number: Int
    let text: String

    init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TokenSection: View {
    @State private var state = TokenStore.load()
    @State private var draft = ""
    @State private var isWorking = false
    @State private var message: String?

    private static let tokenSettings = URL(string: "https://www.are.na/settings/personal-access-tokens")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Private channels")
                .font(.headline)
            Text("Public channels work without a token. For private ones, create a personal access token on are.na and paste it here. It's kept in your keychain.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Create a token on are.na", destination: Self.tokenSettings)

            HStack {
                SecureField("Personal access token", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(message ?? statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if state != .missing {
                    Button("Remove", action: remove)
                        .buttonStyle(.link)
                        .disabled(isWorking)
                }
            }
        }
    }

    private var statusText: String {
        switch state {
        case .missing: "No token saved."
        case .saved: "Token saved."
        case .inaccessible: "A token is saved, but this build of the app can't read it. Paste it again."
        }
    }

    /// The widget extension reads the token too, so it goes on the item's access list.
    private var extensionPath: String? {
        Bundle.main.builtInPlugInsURL?
            .appending(path: "ArenaWidgetExtension.appex")
            .path(percentEncoded: false)
    }

    private func save() {
        let token = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !isWorking else { return }
        isWorking = true
        message = "Checking token…"
        Task {
            defer { isWorking = false }
            do {
                let user = try await ArenaClient(token: token).me()
                try TokenStore.save(token, trustedPaths: extensionPath.map { [$0] } ?? [])
                draft = ""
                state = TokenStore.load()
                message = "Token saved for \(user.name ?? user.slug ?? "your account")."
                WidgetCenter.shared.reloadAllTimelines()
            } catch ArenaError.unauthorized {
                message = "Are.na didn't accept that token."
            } catch {
                message = "Couldn't save the token: \(error.localizedDescription)"
            }
        }
    }

    private func remove() {
        do {
            try TokenStore.delete()
            state = TokenStore.load()
            message = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            message = "Couldn't remove the token: \(error.localizedDescription)"
        }
    }
}
