import NotchKit
import ServiceManagement
import SwiftUI

/// The preferences window: which service to ask, and whether to open at login.
struct PreferencesView: View {
    @State private var draft = AppSettings.serviceURL.absoluteString
    @State private var check: Check = .idle
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?

    private enum Check: Equatable {
        case idle
        case checking
        case working(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("Service URL", text: $draft, prompt: Text(AppSettings.defaultServiceURL.absoluteString))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                HStack(alignment: .firstTextBaseline) {
                    checkLine
                    Spacer()
                    Button("Use Default") {
                        draft = AppSettings.defaultServiceURL.absoluteString
                        save()
                    }
                    .disabled(draft == AppSettings.defaultServiceURL.absoluteString)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(parsedDraft == nil || parsedDraft == AppSettings.serviceURL)
                }
            } header: {
                Text("Now-playing service")
            } footer: {
                Text("The address of your now-playing Worker. It answers with what you're listening to; no keys or accounts live in this app.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginNote {
                    HStack(alignment: .firstTextBaseline) {
                        Text(loginNote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            refreshLoginNote()
            await verify(AppSettings.serviceURL)
        }
    }

    @ViewBuilder private var checkLine: some View {
        switch check {
        case .idle:
            EmptyView()
        case .checking:
            Text("Checking…").foregroundStyle(.secondary)
        case .working(let summary):
            Label(summary, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    /// The draft as an http(s) URL, or nil if it isn't one.
    private var parsedDraft: URL? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil else {
            return nil
        }
        return url
    }

    private func save() {
        guard let url = parsedDraft else {
            check = .failed("That isn't a web address.")
            return
        }
        AppSettings.setServiceURL(url)
        Task { await verify(url) }
    }

    /// Asks the service once and says what came back, so a typo shows up
    /// here instead of as a notch that never appears.
    private func verify(_ url: URL) async {
        check = .checking
        do {
            let answer = try await NowPlayingClient().fetch(from: url)
            let track = answer.track ?? "no tracks yet"
            check = .working(answer.playing ? "Working: playing \(track)" : "Working: last played \(track)")
        } catch NowPlayingError.status(let code) {
            check = .failed("The service answered with an error (\(code)).")
        } catch is DecodingError {
            check = .failed("That address answered, but not with now-playing data.")
        } catch {
            check = .failed(error.localizedDescription)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginNote = error.localizedDescription
        }
        // Show what macOS actually did, which isn't always what was asked.
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshLoginNote()
    }

    private func refreshLoginNote() {
        if SMAppService.mainApp.status == .requiresApproval {
            loginNote = "macOS needs you to allow it in Login Items."
        } else if loginNote != nil, SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .notRegistered {
            loginNote = nil
        }
    }
}
