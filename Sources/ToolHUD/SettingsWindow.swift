import AppKit
import SwiftUI
import ToolHUDKit

/// The panes, down the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, buttons, triggers

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.circle"
        case .buttons: "square.grid.2x2"
        case .triggers: "cursorarrow.click.2"
        }
    }
}

/// Settings in an AppKit window with a sidebar, so the Dock menu and the menu bar item can
/// open it (SwiftUI's Settings scene can't be opened from AppKit).
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    fileprivate let selection = PaneSelection()

    func show(_ pane: SettingsPane? = nil) {
        LensDirectory.shared.refresh()
        LaunchAtLogin.shared.refresh()
        if let pane { selection.pane = pane }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRoot(selection: selection))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = false
            window.setContentSize(NSSize(width: 900, height: 640))
            window.contentMinSize = NSSize(width: 780, height: 520)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ToolHUDSettings")
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.title = selection.pane.title
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    fileprivate func paneChanged(_ pane: SettingsPane) {
        window?.title = pane.title
    }
}

@Observable
@MainActor
final class PaneSelection {
    var pane: SettingsPane = .appearance
}

struct SettingsRoot: View {
    @State var selection: PaneSelection

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding<SettingsPane?>(get: { selection.pane },
                                                                          set: { if let p = $0 { selection.pane = p } })) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                switch selection.pane {
                case .general: GeneralSettings()
                case .appearance: AppearanceSettings()
                case .buttons: ButtonsSettings()
                case .triggers: TriggersSettings()
                }
                Text("\(AppInfo.name) \(AppInfo.displayVersion)")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .onChange(of: selection.pane) { _, pane in SettingsWindow.shared.paneChanged(pane) }
    }
}

/// A slider with its label and current value.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                // Rounded here rather than with Slider's `step`, which draws a tick mark for
                // every step.
                Slider(value: Binding(get: { value }, set: { new in
                    value = step.map { (new / $0).rounded() * $0 } ?? new
                }), in: range)
                Text(format(value)).monospacedDigit().frame(width: 58, alignment: .trailing).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @State private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Visualization") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                    ForEach(Visualization.allCases) { viz in
                        VisualizationCard(visualization: viz, slots: prefs.visibleSlots, opacity: prefs.opacity,
                                          selected: prefs.visualization == viz) {
                            prefs.visualization = viz
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Number of buttons") {
                    Stepper(value: $prefs.slotCount, in: DefaultRing.minCount...DefaultRing.maxCount) {
                        Text("\(prefs.slotCount)").monospacedDigit()
                    }
                }
                ValueSlider(title: "Opacity", value: $prefs.opacity, range: 0.2...1, step: 0.05,
                            format: { "\(Int(($0 * 100).rounded()))%" })
                Picker("Size", selection: $prefs.size) {
                    ForEach(HUDSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Open at", selection: $prefs.anchor) {
                    ForEach(HUDAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Play a soft sound when a button runs", isOn: $prefs.playSound)
                Toggle("Trackpad haptic as you move between buttons", isOn: $prefs.haptics)
                LabeledContent("Try it") {
                    Button("Show HUD") { HUDController.shared.show(atScreenCenter: true) }
                }
            } footer: {
                Text("Fewer buttons are faster to aim at. Near a screen edge the HUD moves inward so every button stays on screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// One visualization, drawn for real at a quarter of its size.
struct VisualizationCard: View {
    let visualization: Visualization
    let slots: [Slot]
    let opacity: Double
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                HUDDrawing(model: HUDModel(preview: visualization, slots: slots, opacity: opacity))
                    .scaleEffect(0.26)
                    .frame(width: 156, height: 156)
                    .frame(maxWidth: .infinity)
                    .background(visualization == .glassPills ? Color(hex: "#E9EBF0") : Color(hex: "#101216"),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                HStack(alignment: .firstTextBaseline) {
                    Text(visualization.title).font(.headline)
                    Spacer()
                    Text(visualization.family == .ring ? "Ring" : "Buttons").font(.caption).foregroundStyle(.secondary)
                }
                Text(visualization.blurb).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(visualization.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - General

struct GeneralSettings: View {
    @State private var prefs = Preferences.shared
    @State private var presence = PresenceSettings.shared
    @State private var login = LaunchAtLogin.shared
    @State private var confirmReset = false
    @State private var sync = SettingsSync.shared
    @State private var updater = AutoUpdater.shared

    private var updateFooter: String {
        switch updater.policy {
        case .automatic:
            "ToolHUD checks every 30 minutes. A new version installs itself when the HUD hasn't been used for 30 minutes, no app is presenting or keeping the screen awake, and your Mac hasn't been used for 2 minutes. You'll get a notification when it's done."
        case .ask:
            "ToolHUD checks every 30 minutes and sends a notification when a new version is out. Nothing installs until you choose to."
        case .off:
            "ToolHUD won't look for updates on its own. Use Check Now whenever you like."
        }
    }

    var body: some View {
        Form {
            Section("Where ToolHUD appears") {
                Toggle("Show in Dock", isOn: $presence.showInDock)
                Toggle("Show in menu bar", isOn: $presence.showInMenuBar)
                if !presence.showInDock && !presence.showInMenuBar {
                    Text(AppPresence.hiddenEverywhereNote(appName: "ToolHUD", settingsName: "Settings"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Open ToolHUD at login", isOn: Binding(get: { login.isEnabled }, set: { login.set($0) }))
                if login.needsApproval {
                    Button("Allow in Login Items…") { login.openLoginItemsSettings() }
                }
                if let error = login.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Sync settings with your other Macs", isOn: $sync.isEnabled)
                if sync.isEnabled {
                    switch sync.keyState {
                    case .ready:
                        LabeledContent {
                            Button("Sync Now") { sync.syncNow() }
                        } label: {
                            if let error = sync.lastError {
                                Text(error).foregroundStyle(.red)
                            } else if let date = sync.lastSynced {
                                Text("Synced \(date.formatted(date: .omitted, time: .shortened))\(sync.lastSource.map { $0 == SettingsSync.deviceName ? "" : " from \($0)" } ?? "")")
                            } else {
                                Text("Waiting for iCloud Drive…")
                            }
                        }
                        SyncPassphraseForm(mode: .change)
                    case .needsNewPassphrase, .needsPassphrase:
                        SyncPassphraseForm(mode: sync.keyState == .needsPassphrase ? .enter : .create)
                            .id(sync.keyState == .needsPassphrase)
                    case .inactive:
                        Text(sync.lastError ?? "Checking iCloud Drive…").foregroundStyle(sync.lastError == nil ? Color.secondary : Color.red)
                    }
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Your buttons, look, shortcut and triggers follow you to every Mac signed in to the same iCloud account with sync turned on. They're encrypted on this Mac with your sync passphrase before they reach iCloud Drive, so neither Apple nor the developer can read them. Open at login stays on each Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("When an update is available", selection: $updater.policy) {
                    ForEach(UpdatePolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if let staged = updater.staged {
                    LabeledContent("Version \(staged.version) is ready") {
                        Button("Install Now") { updater.installNow() }
                    }
                }
                LabeledContent("Version \(AppInfo.displayVersion)") {
                    Button("Check Now") { UpdateController.checkForUpdates() }
                }
                if let error = updater.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                if updater.policy != .off && !updater.notificationsAllowed {
                    LabeledContent {
                        Button("Open Notification Settings") { AutoUpdater.openNotificationSettings() }
                    } label: {
                        Label("Notifications are off for ToolHUD, so update news only shows in the menu.",
                              systemImage: "bell.slash").foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(updateFooter).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("About") {
                    HStack {
                        Button("About ToolHUD") {
                            NSApp.activate(ignoringOtherApps: true)
                            NSApp.orderFrontStandardAboutPanel(nil)
                        }
                        Button("Our other apps…") {
                            if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
                LabeledContent("All ToolHUD settings") {
                    Button("Reset to Defaults…") { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh(); updater.refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updater.refreshNotificationStatus()
        }
        .confirmationDialog("Reset ToolHUD settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                prefs.resetToDefaults()
                HotKeyCenter.shared.apply()
                MouseTriggers.shared.apply()
            }
        } message: {
            Text("Your buttons, look, shortcut and triggers go back to how ToolHUD started. Where it appears, login and sync stay as they are.")
        }
    }
}

/// Sets up, enters or changes the sync passphrase.
struct SyncPassphraseForm: View {
    enum Mode { case create, enter, change, startOver }

    @State var mode: Mode
    @State private var sync = SettingsSync.shared
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var error: String?
    @State private var changing = false
    @State private var confirmStartOver = false

    private var needsConfirm: Bool { mode != .enter }
    private var valid: Bool {
        mode == .enter ? !passphrase.isEmpty : passphrase.count >= 8 && confirm == passphrase
    }

    var body: some View {
        if mode == .change && !changing {
            LabeledContent("Encrypted with your sync passphrase") {
                Button("Change Passphrase…") { changing = true }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt).fixedSize(horizontal: false, vertical: true)
                SecureField("", text: $passphrase, prompt: Text(mode == .enter ? "Passphrase" : "New passphrase"))
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .textContentType(mode == .enter ? .password : .newPassword)
                    .onSubmit { if valid && !needsConfirm { submit() } }
                if needsConfirm {
                    SecureField("", text: $confirm, prompt: Text("Confirm passphrase"))
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .textContentType(.newPassword)
                        .onSubmit { if valid { submit() } }
                    if !passphrase.isEmpty && passphrase.count < 8 {
                        Text("At least 8 characters.").font(.caption).foregroundStyle(.secondary)
                    } else if !confirm.isEmpty && confirm != passphrase {
                        Text("The passphrases don't match.").font(.caption).foregroundStyle(.red)
                    }
                }
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                HStack {
                    if mode == .enter {
                        Button("Forgot It? Start Over…") { confirmStartOver = true }
                    }
                    if mode == .change || mode == .startOver {
                        Button("Cancel") { reset(to: mode == .startOver ? .enter : .change) }
                    }
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    Button(buttonTitle) { submit() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!valid || working)
                }
            }
            .padding(.vertical, 4)
            .confirmationDialog("Start over with a new passphrase?", isPresented: $confirmStartOver) {
                Button("Start Over", role: .destructive) { reset(to: .startOver) }
            } message: {
                Text("The encrypted settings in iCloud Drive are replaced with this Mac's, and your other Macs will ask for the new passphrase.")
            }
        }
    }

    private var prompt: String {
        switch mode {
        case .create: "Choose a sync passphrase. Your settings are encrypted with it before they go to iCloud Drive, and you'll enter the same passphrase on your other Macs. It never leaves your Macs and can't be recovered, so keep it somewhere safe."
        case .enter: "Your synced settings are encrypted. Enter the sync passphrase you chose on your other Mac."
        case .change: "Choose a new sync passphrase. Your other Macs keep syncing; you'll only need the new one when you set up another Mac."
        case .startOver: "Choose a new sync passphrase. Enter it on your other Macs when they ask."
        }
    }

    private var buttonTitle: String {
        switch mode {
        case .create: "Turn On Encrypted Sync"
        case .enter: "Unlock"
        case .change: "Change Passphrase"
        case .startOver: "Start Over"
        }
    }

    private func reset(to newMode: Mode) {
        mode = newMode
        passphrase = ""
        confirm = ""
        error = nil
        changing = false
    }

    private func submit() {
        guard valid, !working else { return }
        working = true
        error = nil
        let entered = passphrase
        Task {
            defer { working = false }
            do {
                switch mode {
                case .create: try await sync.createPassphrase(entered)
                case .enter: try await sync.enterPassphrase(entered)
                case .change: try await sync.changePassphrase(entered)
                case .startOver: try await sync.createPassphrase(entered, replacing: true)
                }
                reset(to: .change)
            } catch {
                if case SettingsSync.SyncError.alreadySetUp = error { reset(to: .enter) }
                self.error = error.localizedDescription
            }
        }
    }
}

/// `AppPresence` values as observable state for Settings.
@Observable
@MainActor
final class PresenceSettings {
    static let shared = PresenceSettings()

    var showInDock = AppPresence.showInDock {
        didSet {
            AppPresence.showInDock = showInDock
            AppPresence.applyDock(keepInFront: NSApp.keyWindow)
        }
    }

    var showInMenuBar = AppPresence.showInMenuBar {
        didSet { AppPresence.showInMenuBar = showInMenuBar }
    }

    /// Follows choices that arrived from another Mac.
    func reload() {
        if showInDock != AppPresence.showInDock { showInDock = AppPresence.showInDock }
        if showInMenuBar != AppPresence.showInMenuBar { showInMenuBar = AppPresence.showInMenuBar }
        // The status item follows the notification, which the setter only posts on a change.
        NotificationCenter.default.post(name: AppPresence.menuBarDidChange, object: nil)
    }
}
