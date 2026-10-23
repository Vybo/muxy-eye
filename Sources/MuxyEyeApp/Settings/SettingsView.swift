import AppKit
import MuxyEyeCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let settings: AppSettings
    let launchAtLogin: LaunchAtLogin

    @State private var screens = NSScreen.screens

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Expand automatically when an agent needs you", isOn: $settings.autoExpand)
                Picker("Display", selection: $settings.pinnedDisplayID) {
                    Text("Follow focused app").tag(CGDirectDisplayID?.none)
                    ForEach(screens, id: \.self) { screen in
                        if let id = screen.displayID {
                            Text(screen.localizedName).tag(CGDirectDisplayID?.some(id))
                        }
                    }
                }
                LaunchAtLoginToggle(launchAtLogin: launchAtLogin)
            }
            Section("Claude hooks") {
                HooksControls(model: model)
            }
            Section("Muxy") {
                MuxyLocationRows(model: model, settings: settings)
                PathField(
                    title: "Muxy CLI path",
                    prompt: "Detected automatically",
                    value: $settings.muxyPathOverride,
                    onCommit: model.muxySettingsChanged
                )
                PathField(
                    title: "Muxy profile folder (MUXY_DIR)",
                    prompt: "Default profile",
                    value: $settings.muxyProfileDir,
                    onCommit: model.muxySettingsChanged
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            screens = NSScreen.screens
            model.refreshHookStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
    }
}

struct LaunchAtLoginToggle: View {
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        Toggle("Launch at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
        if let error = launchAtLogin.errorText {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}

/// Where Muxy was found, plus the unsupported-protocol warning.
struct MuxyLocationRows: View {
    let model: AppModel
    let settings: AppSettings

    var body: some View {
        Text(SetupText.muxyLocation(path: model.muxyExecutable?.path, buildInfo: model.buildInfo))
            .textSelection(.enabled)
        if let warning = SetupText.unsupportedVersionWarning(model.buildInfo) {
            Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

/// Install, update and remove the Claude hooks, with the settings file in use and the outcome.
struct HooksControls: View {
    let model: AppModel

    var body: some View {
        LabeledContent("Settings file") {
            Text(model.claudeSettingsURL.path).textSelection(.enabled).foregroundStyle(.secondary)
        }
        LabeledContent("Status", value: SetupText.hookStatusTitle(model.hookStatus))
        HStack {
            if let title = SetupText.installButtonTitle(model.hookStatus) {
                Button(title) { model.installHooks() }
            }
            if SetupText.canRemoveHooks(model.hookStatus) {
                Button("Remove") { model.removeHooks() }
            }
        }
        Text(SetupText.restartHint).font(.caption).foregroundStyle(.secondary)
        if let error = model.hookError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}

/// A text field that applies its value when the user presses Return or leaves the field.
struct PathField: View {
    let title: String
    let prompt: String
    @Binding var value: String?
    let onCommit: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .focused($focused)
            .onAppear { text = value ?? "" }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = trimmed.isEmpty ? nil : trimmed
        guard new != value else { return }
        value = new
        onCommit()
    }
}
