import MuxyEyeCore
import SwiftUI

/// First-launch setup: find Muxy, install the Claude hooks, launch at login.
struct OnboardingView: View {
    let model: AppModel
    let settings: AppSettings
    let launchAtLogin: LaunchAtLogin
    let onDone: () -> Void

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Muxy Eye").font(.title2.bold())

            step("1. Muxy") {
                MuxyLocationRows(model: model, settings: settings)
                if model.muxyExecutable == nil {
                    PathField(
                        title: "Muxy CLI path",
                        prompt: "/path/to/muxy",
                        value: $settings.muxyPathOverride,
                        onCommit: model.muxySettingsChanged
                    )
                }
            }

            step("2. Claude hooks") {
                Text("Hooks tell Muxy Eye the moment an agent needs you.").foregroundStyle(.secondary)
                HooksControls(model: model)
                Text(SetupText.restartHint).font(.caption).foregroundStyle(.secondary)
            }

            step("3. Startup") {
                LaunchAtLoginToggle(launchAtLogin: launchAtLogin)
            }

            HStack {
                Spacer()
                Button("Done") { onDone() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshHookStatus() }
    }

    private func step<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }
}
