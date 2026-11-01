import AppKit
import SwiftUI
import ToolHUDKit
import UniformTypeIdentifiers

// MARK: - Buttons

/// The buttons on the HUD in order, and the one chosen beside the list. With the
/// button pad on, a switch above the list moves between the ring's buttons and the pad's.
struct ButtonsSettings: View {
    @State private var prefs = Preferences.shared
    @State private var directory = LensDirectory.shared
    @State private var selection: Int? = 0
    @State private var importError: String?
    @State private var list: ButtonList = .ring
    /// The button the right-click menu or the Delete key asked to delete, while the
    /// confirmation is up.
    @State private var pendingDelete: Int?
    /// Whose ring is being edited: "" for every app, else an app's bundle identifier.
    @State private var ringFor = ""
    @State private var confirmRemoveRing = false

    /// The app ring being edited, while rings for each app are on.
    private var ringIndex: Int? {
        guard prefs.appRingsEnabled, !ringFor.isEmpty else { return nil }
        return prefs.appRings.firstIndex { $0.bundleID == ringFor }
    }

    // The lists being edited: the usual ones, or the chosen app's.
    private var ringSlots: [Slot] {
        get { ringIndex.map { prefs.appRings[$0].slots } ?? prefs.slots }
        nonmutating set { if let i = ringIndex { prefs.appRings[i].slots = newValue } else { prefs.slots = newValue } }
    }
    private var ringSlotCount: Int {
        get { ringIndex.map { prefs.appRings[$0].slotCount } ?? prefs.slotCount }
        nonmutating set { if let i = ringIndex { prefs.appRings[i].slotCount = newValue } else { prefs.slotCount = newValue } }
    }
    private var ringPadSlots: [Slot] {
        get { ringIndex.map { prefs.appRings[$0].padSlots } ?? prefs.padSlots }
        nonmutating set { if let i = ringIndex { prefs.appRings[i].padSlots = newValue } else { prefs.padSlots = newValue } }
    }
    private var ringPadCount: Int {
        get { ringIndex.map { prefs.appRings[$0].padCount } ?? prefs.padCount }
        nonmutating set { if let i = ringIndex { prefs.appRings[i].padCount = newValue } else { prefs.padCount = newValue } }
    }

    enum ButtonList: String, CaseIterable {
        case ring, pad
        var title: String { rawValue.capitalized }
    }

    /// The pad's list, only while the pad is on.
    private var editingPad: Bool { list == .pad && prefs.padEnabled }
    private var count: Int { editingPad ? ringPadCount : ringSlotCount }
    private var limits: ClosedRange<Int> {
        editingPad ? DefaultPad.minCount...DefaultPad.maxCount : DefaultRing.minCount...DefaultRing.maxCount
    }
    private var index: Int { min(selection ?? 0, count - 1) }

    private var slot: Binding<Slot> {
        let i = index
        if editingPad {
            return Binding(get: { ringPadSlots[i] }, set: { ringPadSlots[i] = $0 })
        }
        return Binding(get: { ringSlots[i] }, set: { ringSlots[i] = $0 })
    }

    private func setCount(_ value: Int) {
        if editingPad { ringPadCount = value } else { ringSlotCount = value }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                if prefs.appRingsEnabled {
                    appRingBar
                    Divider()
                }
                if prefs.padEnabled {
                    Picker("", selection: $list) {
                        ForEach(ButtonList.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(8)
                    Divider()
                }
                List(selection: $selection) {
                    if editingPad {
                        ForEach(Array(ringPadSlots.prefix(ringPadCount).enumerated()), id: \.element.id) { i, item in
                            SlotRow(key: DefaultPad.keyLetters[i], slot: item).tag(i)
                                .contextMenu { rowMenu(i) }
                        }
                        .onMove { from, to in ringPadSlots.move(fromOffsets: from, toOffset: to) }
                    } else {
                        ForEach(Array(ringSlots.prefix(ringSlotCount).enumerated()), id: \.element.id) { i, item in
                            SlotRow(key: "\(i + 1)", slot: item).tag(i)
                                .contextMenu { rowMenu(i) }
                        }
                        .onMove { from, to in ringSlots.move(fromOffsets: from, toOffset: to) }
                    }
                }
                .onDeleteCommand { if count > limits.lowerBound { pendingDelete = index } }
                .alert(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                    Button("Delete", role: .destructive) {
                        if let i = pendingDelete { delete(i) }
                        pendingDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                        .keyboardShortcut(.defaultAction)
                } message: {
                    Text("Its action, symbol and color are removed, and the buttons after it move up.")
                }
                Divider()
                HStack {
                    Button { setCount(max(limits.lowerBound, count - 1)) } label: { Image(systemName: "minus") }
                        .disabled(count <= limits.lowerBound)
                        .help("Remove the last button")
                    Button { setCount(min(limits.upperBound, count + 1)); selection = count - 1 } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(count >= limits.upperBound)
                    .help("Add a button")
                    Spacer()
                    Text("\(count) of \(limits.upperBound)").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 240)
            Divider()
            SlotEditor(slot: slot,
                       title: editingPad ? "Pad button \(DefaultPad.keyLetters[index])" : "Button \(index + 1)",
                       reset: {
                           if editingPad { ringPadSlots[index] = DefaultPad.slots[index] } else { ringSlots[index] = DefaultRing.slots[index] }
                       },
                       importRing: importRing, exportRing: exportRing, importError: importError)
        }
        .onChange(of: list) { _, _ in selection = 0 }
        .onChange(of: ringFor) { _, _ in selection = 0 }
        .onChange(of: prefs.appRingsEnabled) { _, on in if !on { ringFor = "" } }
        .confirmationDialog("Remove the ring for \(ringIndex.map { prefs.appRings[$0].name } ?? "this app")?",
                            isPresented: $confirmRemoveRing) {
            Button("Remove", role: .destructive) {
                prefs.appRings.removeAll { $0.bundleID == ringFor }
                ringFor = ""
            }
        } message: {
            Text("The app goes back to the usual buttons.")
        }
        .onChange(of: prefs.padEnabled) { _, on in if !on { list = .ring; selection = 0 } }
        #if DEBUG
        .onAppear { if let button = DebugHooks.selectedButton { selection = button } }
        #endif
    }

    // MARK: Rings for each app

    /// Which ring the list shows, with adding and removing apps.
    private var appRingBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: $ringFor) {
                Text("All apps").tag("")
                if !prefs.appRings.isEmpty { Divider() }
                ForEach(prefs.appRings) { ring in Text(ring.name).tag(ring.bundleID) }
            }
            .labelsHidden()
            Button { addAppRing() } label: { Image(systemName: "plus") }
                .help("Add a ring for an app")
            Button { confirmRemoveRing = true } label: { Image(systemName: "minus") }
                .disabled(ringIndex == nil)
                .help("Remove this app's ring")
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    /// Picks an app and starts its ring as a copy of the usual buttons.
    private func addAppRing() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the app that gets its own buttons."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        if prefs.appRings.contains(where: { $0.bundleID == id }) {
            ringFor = id
            return
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let ring = AppRing.copying(bundleID: id, name: name, slots: prefs.slots, slotCount: prefs.slotCount,
                                   padSlots: prefs.padSlots, padCount: prefs.padCount)
        prefs.appRings = (prefs.appRings + [ring]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ringFor = id
    }

    // MARK: Right-click menu

    @ViewBuilder
    private func rowMenu(_ i: Int) -> some View {
        Button("Test This Button") {
            let toRun = editingPad ? ringPadSlots[i] : ringSlots[i]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { ActionRunner.run(toRun) }
            }
        }
        Button("Duplicate Button") { duplicate(i) }
            .disabled(count >= limits.upperBound)
        Divider()
        Button("Delete Button…", role: .destructive) { pendingDelete = i }
            .disabled(count <= limits.lowerBound)
    }

    private var deleteTitle: String {
        guard let i = pendingDelete else { return "Delete this button?" }
        let list = editingPad ? ringPadSlots : ringSlots
        let name = list.indices.contains(i) ? list[i].name : "this button"
        return "Delete “\(name)”?"
    }

    private func delete(_ i: Int) {
        if editingPad {
            var slots = ringPadSlots, count = ringPadCount
            SlotListEdit.delete(at: i, slots: &slots, count: &count, minCount: limits.lowerBound)
            ringPadSlots = slots; ringPadCount = count
        } else {
            var slots = ringSlots, count = ringSlotCount
            SlotListEdit.delete(at: i, slots: &slots, count: &count, minCount: limits.lowerBound)
            ringSlots = slots; ringSlotCount = count
        }
        selection = min(selection ?? 0, count - 1)
    }

    private func duplicate(_ i: Int) {
        if editingPad {
            var slots = ringPadSlots, count = ringPadCount
            SlotListEdit.duplicate(at: i, slots: &slots, count: &count, maxCount: limits.upperBound)
            ringPadSlots = slots; ringPadCount = count
        } else {
            var slots = ringSlots, count = ringSlotCount
            SlotListEdit.duplicate(at: i, slots: &slots, count: &count, maxCount: limits.upperBound)
            ringSlots = slots; ringSlotCount = count
        }
        selection = i + 1
    }

    private func exportRing() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My ToolHUD ring.\(RingFile.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: RingFile.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let ring = RingFile(visualization: prefs.visualization, slots: Array(ringSlots.prefix(ringSlotCount)),
                                pad: prefs.padEnabled ? Array(ringPadSlots.prefix(ringPadCount)) : nil,
                                padPosition: prefs.padEnabled ? prefs.padPosition : nil)
            try ring.encoded().write(to: url, options: .atomic)
        } catch {
            importError = "The ring couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func importRing() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: RingFile.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let ring = try RingFile.decode(Data(contentsOf: url))
            if let i = ringIndex {
                // Into the app's ring: its buttons and pad, leaving the look alone.
                let app = prefs.appRings[i]
                prefs.appRings[i] = AppRing(bundleID: app.bundleID, name: app.name, slots: ring.slots, slotCount: ring.slots.count,
                                            padSlots: ring.pad ?? app.padSlots, padCount: ring.pad?.count ?? app.padCount)
            } else {
                prefs.adopt(ring)
            }
            list = .ring
            selection = 0
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}

struct SlotRow: View {
    /// The key that runs it in the HUD.
    let key: String
    let slot: Slot

    var body: some View {
        HStack(spacing: 10) {
            SlotGlyph(symbol: slot.symbol, size: 13, color: slot.tint.color)
                .frame(width: 26, height: 26)
                .background(slot.tint.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.name).lineLimit(1)
                Text(slot.mode == .keystroke ? (slot.keySequence?.display ?? "Keystroke") : slot.sourceName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(key).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Where a button being edited lives, which decides what it may be.
enum EditorContext {
    /// On the ring or the pad.
    case ring
    /// Inside a folder: no folders within folders.
    case folder
    /// A step of a Steps button: nothing that waits for the user.
    case step
}

/// Everything about one button.
struct SlotEditor: View {
    @Binding var slot: Slot
    let title: String
    var context: EditorContext = .ring
    var reset: (() -> Void)? = nil
    var importRing: (() -> Void)? = nil
    var exportRing: (() -> Void)? = nil
    var importError: String? = nil

    @State private var directory = LensDirectory.shared
    @State private var prefs = Preferences.shared
    @State private var choosingSymbol = false
    @State private var editingFolder = false
    @State private var editingStep: Int?
    @State private var shortcutNames: [String] = []

    /// The kinds this button may be: folders and app menus only while they're turned on,
    /// and never a kind the context rules out. The current kind always stays listed.
    private var modes: [ActionMode] {
        ActionMode.allCases.filter { mode in
            if mode == slot.mode { return true }
            switch mode {
            case .folder: return context == .ring && prefs.foldersEnabled
            case .appMenu: return context != .step && prefs.appMenuButtonsEnabled
            case .chain: return context != .step
            default: return true
            }
        }
    }

    var body: some View {
        Form {
            Section(title) {
                TextField("Name", text: $slot.name)
                LabeledContent("Symbol") {
                    HStack {
                        SlotGlyph(symbol: slot.symbol, size: 16, color: slot.tint.color)
                            .frame(width: 30, height: 30)
                            .background(slot.tint.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        TextField("", text: $slot.symbol, prompt: Text("SF Symbol name"))
                            .labelsHidden().frame(maxWidth: 190)
                        Button("Choose…") { choosingSymbol = true }
                            .popover(isPresented: $choosingSymbol, arrowEdge: .bottom) {
                                SymbolPicker(symbol: $slot.symbol, color: slot.tint.color) { choosingSymbol = false }
                            }
                    }
                }
                if context != .step {
                    LabeledContent("Color") {
                        HStack(spacing: 8) {
                            Button("App color") { slot.color = nil }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(slot.color == nil)
                            ForEach(SlotColor.swatches, id: \.name) { swatch in
                                Button { slot.color = swatch.color } label: {
                                    Circle().fill(swatch.color.color).frame(width: 20, height: 20)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(slot.color == swatch.color ? 0.9 : 0), lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(swatch.name)
                            }
                            ColorPicker("", selection: Binding(get: { slot.tint.color },
                                                               set: { slot.color = SlotColor(NSColor($0)) }),
                                        supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                }
            }

            Section {
                Picker("When chosen", selection: Binding(get: { slot.mode }, set: { change(to: $0) })) {
                    ForEach(modes, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                switch slot.mode {
                case .lens: lensFields
                case .keystroke: keystrokeFields
                case .shortcut: shortcutFields
                case .open: openFields
                case .text: textFields
                case .menuItem: menuItemFields
                case .script: scriptFields
                case .chain: stepsFields
                case .folder: folderFields
                case .appMenu: appMenuFields
                }
            } footer: {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }

            if context == .ring || reset != nil {
                Section {
                    HStack {
                        Button("Test This Button") {
                            let toRun = slot
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                MainActor.assumeIsolated { ActionRunner.run(toRun) }
                            }
                        }
                        .disabled(slot.mode == .folder)
                        if let reset { Button("Reset Button") { reset() } }
                        Spacer()
                        if let importRing { Button("Import Ring…") { importRing() } }
                        if let exportRing { Button("Export Ring…") { exportRing() } }
                    }
                    if let importError {
                        Text(importError).font(.callout).foregroundStyle(.red)
                    }
                } footer: {
                    if importRing != nil {
                        Text("A ring file holds your buttons, the button pad and the HUD's look, to keep or to share with someone else.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editingFolder) {
            FolderEditor(folder: $slot) { editingFolder = false }
        }
        .sheet(isPresented: Binding(get: { editingStep != nil }, set: { if !$0 { editingStep = nil } })) {
            if let i = editingStep, slot.steps?.indices.contains(i) == true {
                StepEditor(step: Binding(get: { slot.steps?[i] ?? ChainStep(action: .empty()) },
                                         set: { if slot.steps?.indices.contains(i) == true { slot.steps?[i] = $0 } }),
                           number: i + 1) { editingStep = nil }
            }
        }
    }

    private var footer: String {
        switch slot.mode {
        case .lens: "A lens action asks the app to run the feature directly, so it keeps working if you change the app's shortcuts."
        case .keystroke: "A keystroke presses keys for you, as if you'd typed them. The HUD never takes focus, so they go to the app that was in front when it opened."
        case .shortcut: "Runs a shortcut from the Shortcuts app, in the background, as the Shortcuts menu does."
        case .open: "Opens a web page in your browser, or a file, folder or app as double-clicking it would."
        case .text: "Puts the text into the app that was in front, as if you'd typed it. Pasting is faster for long text and leaves your clipboard as it was."
        case .menuItem: "Chooses a menu item in the app that was in front, or in the app you pick, as clicking it would. Write the menus in order, separated by >."
        case .script: "Runs in the background. The first time a script controls another app, macOS asks whether ToolHUD may."
        case .chain: "Runs each step in turn, waiting after each for as long as you set, so an app has time to catch up."
        case .folder: "Opens a smaller ring of up to 12 more buttons in place of this one. Esc goes back."
        case .appMenu: "Shows one of our apps' menus right at the pointer: the same menu as in ToolHUD's menu bar item."
        }
    }

    /// Starts a kind with something sensible: a new folder or list of steps isn't empty, and
    /// a symbol or name the user never changed follows the new kind.
    private func change(to mode: ActionMode) {
        let oldSymbol = slot.mode.symbol
        slot.mode = mode
        if slot.symbol == "plus.circle" || slot.symbol == oldSymbol { slot.symbol = mode.symbol }
        switch mode {
        case .folder where (slot.children ?? []).isEmpty:
            slot.children = [Slot.empty(), Slot.empty()]
        case .chain where (slot.steps ?? []).isEmpty:
            slot.steps = [ChainStep(action: .empty())]
        case .appMenu where slot.menuApp == nil:
            if let first = MenuHubHost.shared.guests().first, let id = first.bundleIdentifier {
                slot.menuApp = id
                slot.menuAppName = MenuHubHost.name(of: first)
            }
        default:
            break
        }
    }

    // MARK: Lens action

    @ViewBuilder private var lensFields: some View {
        Picker("App", selection: Binding(get: { slot.lensApp ?? "" }, set: { chooseApp($0) })) {
            if slot.lensApp == nil { Text("Choose an app").tag("") }
            ForEach(directory.apps) { app in
                Text(directory.installed[app.id] == nil ? "\(app.name) (not installed)" : app.name).tag(app.id)
            }
        }
        if let id = slot.lensApp, let app = directory.app(id) {
            Picker("Feature", selection: Binding(get: { slot.lensFeature ?? "" }, set: { chooseFeature($0, in: app) })) {
                if slot.lensFeature == nil { Text("Choose a feature").tag("") }
                ForEach(app.features) { Text($0.title).tag($0.id) }
            }
        }
        let status = directory.status(of: slot)
        Label(status.text, systemImage: status.ok ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(status.ok ? Color.secondary : Color.orange)
        if let id = slot.lensApp, let app = directory.app(id), directory.installed[id] == nil {
            LabeledContent("") {
                Link("Get \(app.name) \(app.downloadURL == nil ? "at stevemanke.com" : "on GitHub")",
                     destination: LensDirectory.webPage(for: app))
            }
            .font(.callout)
        }
    }

    /// A new app starts at its first feature.
    private func chooseApp(_ id: String) {
        guard !id.isEmpty, id != slot.lensApp, let app = directory.app(id) else { return }
        let old = currentFeature
        slot.lensApp = id
        slot.lensFeature = nil
        if let first = app.features.first { chooseFeature(first.id, in: app, replacing: old) }
    }

    /// Keeps a name or symbol the user typed; ones that came from the old feature follow the new.
    private func chooseFeature(_ id: String, in app: LensApp, replacing old: LensFeature? = nil) {
        guard let feature = app.feature(id) else { return }
        let previous = old ?? currentFeature
        if previous == nil || slot.name == previous?.shortTitle || slot.name == "New button" { slot.name = feature.shortTitle }
        if previous == nil || slot.symbol == previous?.symbol || slot.symbol == "plus.circle" || slot.symbol == ActionMode.lens.symbol {
            slot.symbol = feature.symbol
        }
        slot.lensFeature = id
        if slot.shortcut == nil { slot.shortcut = feature.shortcut }
    }

    private var currentFeature: LensFeature? {
        slot.lensApp.flatMap { directory.app($0) }?.feature(slot.lensFeature ?? "")
    }

    // MARK: Keystroke

    @ViewBuilder private var keystrokeFields: some View {
        KeystrokeFields(slot: $slot)
        if slot.keySequence?.keys.count == 1, let first = slot.keySequence?.first, let hud = prefs.hotKey, first.sameKeys(as: hud) {
            Label("That's the shortcut that opens ToolHUD, so this button would just reopen the HUD.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
        SendToPicker(slot: $slot)
    }

    // MARK: Shortcut

    @ViewBuilder private var shortcutFields: some View {
        Picker("Shortcut", selection: Binding(get: { slot.shortcutName ?? "" }, set: { chooseShortcut($0) })) {
            if (slot.shortcutName ?? "").isEmpty { Text("Choose a shortcut").tag("") }
            if let name = slot.shortcutName, !name.isEmpty, !shortcutNames.contains(name) { Text(name).tag(name) }
            ForEach(shortcutNames, id: \.self) { Text($0).tag($0) }
        }
        .onAppear { SearchSource.loadShortcuts { shortcutNames = $0 } }
        if shortcutNames.isEmpty {
            Text("Make shortcuts in the Shortcuts app, and they appear here.")
                .font(.callout).foregroundStyle(.secondary)
        }
        LabeledContent("") {
            Button("Open Shortcuts") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    private func chooseShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        if slot.name == "New button" || slot.name == slot.shortcutName { slot.name = name }
        slot.shortcutName = name
    }

    // MARK: Open

    @ViewBuilder private var openFields: some View {
        LabeledContent("Open") {
            HStack {
                TextField("", text: Binding(get: { displayedOpenTarget }, set: { slot.openTarget = $0.isEmpty ? nil : $0 }),
                          prompt: Text("A web address, or choose a file"))
                    .labelsHidden()
                Button("Choose…") { chooseOpenTarget() }
            }
        }
    }

    /// A chosen file shows as its path; a web address as typed.
    private var displayedOpenTarget: String {
        guard let target = slot.openTarget else { return "" }
        if let url = URL(string: target), url.isFileURL { return url.path }
        return target
    }

    private func chooseOpenTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        if slot.name == "New button" || slot.openTarget.map(Slot.openTargetName) == slot.name { slot.name = name }
        slot.openTarget = url.path
    }

    // MARK: Type text

    @ViewBuilder private var textFields: some View {
        LabeledContent("Text") {
            TextEditor(text: Binding(get: { slot.text ?? "" }, set: { slot.text = $0 }))
                .font(.body)
                .frame(minHeight: 70, maxHeight: 140)
                .multilineTextAlignment(.leading)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        Picker("How", selection: $slot.textMethod) {
            ForEach(TextMethod.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        SendToPicker(slot: $slot)
    }

    // MARK: Menu item

    @ViewBuilder private var menuItemFields: some View {
        LabeledContent("Menu item") {
            HStack {
                TextField("", text: Binding(get: { slot.menuPath.map(MenuPath.display) ?? "" },
                                            set: { let path = MenuPath.parse($0); slot.menuPath = path.isEmpty ? nil : path }),
                          prompt: Text("File > Export…"))
                    .labelsHidden()
                MenuPathPickerButton { path in
                    if slot.name == "New button" || slot.name == slot.menuPath?.last { slot.name = path.last ?? slot.name }
                    slot.menuPath = path
                }
            }
        }
        SendToPicker(slot: $slot)
    }

    // MARK: Script

    @ViewBuilder private var scriptFields: some View {
        Picker("Language", selection: $slot.scriptKind) {
            ForEach(ScriptKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        LabeledContent("Script") {
            TextEditor(text: Binding(get: { slot.script ?? "" }, set: { slot.script = $0 }))
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .frame(minHeight: 90, maxHeight: 180)
                .multilineTextAlignment(.leading)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Steps

    @ViewBuilder private var stepsFields: some View {
        let steps = slot.steps ?? []
        ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
            HStack(spacing: 10) {
                Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16)
                SlotGlyph(symbol: step.action.symbol, size: 12, color: step.action.tint.color)
                    .frame(width: 24, height: 24)
                    .background(step.action.tint.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.action.name).lineLimit(1)
                    Text(step.action.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(step.delay == 0 ? "no wait" : "then wait \(step.delay.formatted(.number.precision(.fractionLength(0...2)))) s")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Edit…") { editingStep = i }
                Menu {
                    Button("Move Up") { moveStep(i, by: -1) }.disabled(i == 0)
                    Button("Move Down") { moveStep(i, by: 1) }.disabled(i == steps.count - 1)
                    Button("Duplicate") { slot.steps?.insert(ChainStep(action: step.action.freshCopy(), delay: step.delay), at: i + 1) }
                        .disabled(steps.count >= ChainStep.maxSteps)
                    Divider()
                    Button("Remove", role: .destructive) { slot.steps?.remove(at: i) }.disabled(steps.count <= 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        LabeledContent("") {
            Button("Add Step") {
                slot.steps = steps + [ChainStep(action: .empty())]
                editingStep = steps.count
            }
            .disabled(steps.count >= ChainStep.maxSteps)
        }
    }

    private func moveStep(_ i: Int, by offset: Int) {
        guard var steps = slot.steps, steps.indices.contains(i + offset) else { return }
        steps.swapAt(i, i + offset)
        slot.steps = steps
    }

    // MARK: Folder

    @ViewBuilder private var folderFields: some View {
        let children = slot.children ?? []
        LabeledContent("Buttons inside") {
            HStack {
                Text(children.map(\.name).prefix(4).joined(separator: ", ") + (children.count > 4 ? "…" : ""))
                    .foregroundStyle(.secondary).lineLimit(1)
                Button("Edit Folder…") { editingFolder = true }
            }
        }
        if !prefs.foldersEnabled {
            Label("Folders are turned off, so this button shows a reminder instead. Turn them on in Settings › Features.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
    }

    // MARK: App menu

    @ViewBuilder private var appMenuFields: some View {
        let guests = MenuHubHost.shared.guests()
        Picker("App", selection: Binding(get: { slot.menuApp ?? "" }, set: { id in
            guard let app = guests.first(where: { $0.bundleIdentifier == id }) else { return }
            let name = MenuHubHost.name(of: app)
            if slot.name == "New button" || slot.name == slot.menuAppName { slot.name = name }
            slot.menuApp = id
            slot.menuAppName = name
        })) {
            if slot.menuApp == nil { Text("Choose an app").tag("") }
            if let id = slot.menuApp, !guests.contains(where: { $0.bundleIdentifier == id }) {
                Text("\(slot.menuAppName ?? id) (not running)").tag(id)
            }
            ForEach(guests, id: \.processIdentifier) { app in
                Text(MenuHubHost.name(of: app)).tag(app.bundleIdentifier ?? "")
            }
        }
        if guests.isEmpty {
            Text("Apps show up here while they're running and their menus are in ToolHUD's menu (Settings › General › Gather my other apps’ menus here).")
                .font(.callout).foregroundStyle(.secondary)
        }
        if !prefs.appMenuButtonsEnabled {
            Label("App menu buttons are turned off. Turn them on in Settings › Features.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
    }
}

/// Where keystrokes, typed text and menu items go.
struct SendToPicker: View {
    @Binding var slot: Slot

    var body: some View {
        Picker("Send to", selection: $slot.sendTo) {
            Text("The app you were using").tag(SendTarget.frontmost)
            ForEach(sendTargets, id: \.self) { target in
                if case .app(_, let name) = target { Text(name).tag(target) }
            }
        }
        LabeledContent("") {
            Button("Choose Another App…") { chooseSendTarget() }
        }
    }

    /// Running apps with a Dock icon, plus whatever the button already names.
    private var sendTargets: [SendTarget] {
        var targets = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> SendTarget? in
                guard let id = app.bundleIdentifier else { return nil }
                return .app(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { name(of: $0) < name(of: $1) }
        if case .app = slot.sendTo, !targets.contains(slot.sendTo) { targets.insert(slot.sendTo, at: 0) }
        return targets
    }

    private func name(of target: SendTarget) -> String {
        if case .app(_, let name) = target { return name }
        return ""
    }

    private func chooseSendTarget() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        slot.sendTo = .app(bundleID: id, name: name)
    }
}

/// "Choose from an App" for a Menu item button: a menu of the running apps, each with its
/// menus read through Accessibility when it's opened.
struct MenuPathPickerButton: View {
    let choose: (_ path: [String]) -> Void
    @State private var picker = MenuPathPicker()

    var body: some View {
        Button("Choose…") { picker.show(choose) }
            .help("Pick a menu item from a running app")
    }
}

@MainActor
final class MenuPathPicker: NSObject, NSMenuDelegate {
    private var choose: (([String]) -> Void)?

    private final class AppMenu: NSMenu {
        var pid: pid_t = 0
    }

    func show(_ choose: @escaping ([String]) -> Void) {
        self.choose = choose
        guard AccessibilityTrust.shared.isTrusted else {
            AccessibilityTrust.shared.request()
            return
        }
        let menu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        for app in apps {
            let item = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier ?? "App", action: nil, keyEquivalent: "")
            let submenu = AppMenu(title: item.title)
            submenu.pid = app.processIdentifier
            submenu.delegate = self
            submenu.addItem(NSMenuItem(title: "Reading menus…", action: nil, keyEquivalent: ""))
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let appMenu = menu as? AppMenu else { return }
        menu.removeAllItems()
        let paths = MenuPress.allPaths(in: appMenu.pid)
        if paths.isEmpty {
            menu.addItem(NSMenuItem(title: "No menus found", action: nil, keyEquivalent: ""))
            return
        }
        // Rebuilt as nested submenus, so it reads like the app's own menu bar.
        func submenu(named title: String, in parent: NSMenu) -> NSMenu {
            if let existing = parent.items.first(where: { $0.title == title && $0.submenu != nil })?.submenu { return existing }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title)
            item.submenu = child
            parent.addItem(item)
            return child
        }
        for path in paths {
            var parent: NSMenu = menu
            for name in path.dropLast() { parent = submenu(named: name, in: parent) }
            let item = NSMenuItem(title: path.last ?? "", action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = path
            parent.addItem(item)
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? [String] else { return }
        choose?(path)
    }
}

/// A folder's buttons, in a sheet: the list beside the chosen button, as in Buttons.
struct FolderEditor: View {
    @Binding var folder: Slot
    let done: () -> Void
    @State private var selection: Int? = 0

    private var children: [Slot] { folder.children ?? [] }
    private var index: Int { min(selection ?? 0, max(children.count - 1, 0)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(Array(children.enumerated()), id: \.element.id) { i, item in
                            SlotRow(key: "\(i + 1)", slot: item).tag(i)
                                .contextMenu {
                                    Button("Test This Button") {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            MainActor.assumeIsolated { ActionRunner.run(item) }
                                        }
                                    }
                                    Button("Duplicate Button") { folder.children?.insert(item.freshCopy(), at: i + 1) }
                                        .disabled(children.count >= DefaultRing.maxCount)
                                    Divider()
                                    Button("Delete Button", role: .destructive) { delete(i) }
                                        .disabled(children.count <= DefaultRing.minCount)
                                }
                        }
                        .onMove { from, to in folder.children?.move(fromOffsets: from, toOffset: to) }
                    }
                    Divider()
                    HStack {
                        Button { delete(index) } label: { Image(systemName: "minus") }
                            .disabled(children.count <= DefaultRing.minCount)
                            .help("Remove the selected button")
                        Button {
                            folder.children = children + [.empty()]
                            selection = children.count
                        } label: { Image(systemName: "plus") }
                            .disabled(children.count >= DefaultRing.maxCount)
                            .help("Add a button")
                        Spacer()
                        Text("\(children.count) of \(DefaultRing.maxCount)").font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                }
                .frame(width: 240)
                Divider()
                if children.indices.contains(index) {
                    SlotEditor(slot: Binding(get: { folder.children?[index] ?? .empty() },
                                             set: { if folder.children?.indices.contains(index) == true { folder.children?[index] = $0 } }),
                               title: "\(folder.name) › Button \(index + 1)", context: .folder)
                }
            }
            Divider()
            HStack {
                Text("Folder “\(folder.name)”").font(.headline)
                Spacer()
                Button("Done") { done() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 820, height: 600)
    }

    private func delete(_ i: Int) {
        guard children.count > DefaultRing.minCount, children.indices.contains(i) else { return }
        folder.children?.remove(at: i)
        selection = min(i, children.count - 1)
    }
}

/// One step of a Steps button, in a sheet.
struct StepEditor: View {
    @Binding var step: ChainStep
    let number: Int
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SlotEditor(slot: $step.action, title: "Step \(number)", context: .step)
            Divider()
            HStack {
                ValueSlider(title: "Then wait", value: $step.delay, range: 0...3, step: 0.1,
                            format: { $0 == 0 ? "No wait" : "\($0.formatted(.number.precision(.fractionLength(1)))) s" })
                    .frame(maxWidth: 380)
                Spacer()
                Button("Done") { done() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 600)
    }
}

/// The keys a keystroke button presses: modifier toggles, and a field for the key or keys
/// to press with them. Several keys are pressed one after another, each with the same
/// modifiers held (⌘K then ⌘S).
struct KeystrokeFields: View {
    @Binding var slot: Slot
    @State private var text = ""
    @State private var modifiers: KeyModifiers = []
    @State private var unknown: [String] = []
    @FocusState private var keyFieldFocused: Bool
    /// Records a shortcut pressed in the key field; a text field never sees ⌘, ⌥ or ⌃ keys.
    @State private var recorder: Any?

    /// In the order the user reads them on the keyboard's left side.
    private static let toggles: [(modifier: KeyModifiers, symbol: String, name: String)] = [
        (.command, "command", "Command"), (.option, "option", "Option"),
        (.control, "control", "Control"), (.shift, "shift", "Shift"),
    ]

    var body: some View {
        LabeledContent("Hold") {
            HStack(spacing: 6) {
                ForEach(Self.toggles, id: \.name) { toggle in
                    let on = modifiers.contains(toggle.modifier)
                    Button {
                        if on { modifiers.remove(toggle.modifier) } else { modifiers.insert(toggle.modifier) }
                        save()
                    } label: {
                        // The symbol with its name under it: many people don't know ⌥ from ⌃.
                        VStack(spacing: 2) {
                            Image(systemName: toggle.symbol)
                                .font(.system(size: 13, weight: .semibold))
                            Text(toggle.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(width: 62, height: 40)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(on ? "\(toggle.name) is held" : "Hold \(toggle.name)")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(toggle.name)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
        LabeledContent("Key") {
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("Type a key, like K"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 160)
                    .focused($keyFieldFocused)
                    .onChange(of: text) { _, new in
                        // A typed space would be invisible in the field.
                        let shown = KeySequence.showingSpaces(new)
                        if shown != new { text = shown } else { save() }
                    }
                    .onChange(of: keyFieldFocused) { _, focused in focused ? startRecording() : stopRecording() }
                    .onDisappear { stopRecording() }
                Menu("Special Keys") {
                    ForEach(KeyNames.insertable, id: \.token) { key in
                        Button(key.title) { text += key.token }
                    }
                }
                .fixedSize()
            }
        }
        if let keys = slot.keySequence, !keys.keys.isEmpty {
            LabeledContent("Presses") {
                Text(keys.display).font(.system(.body, design: .monospaced))
            }
        }
        if !unknown.isEmpty {
            Label("No key on this keyboard types \(unknown.joined(separator: " ")), so ToolHUD leaves it out.",
                  systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
        Text("Letters stand for their keys, so K is the K key; turn on Shift to press ⇧ with it. Or press a shortcut such as ⇧⌘Space in the field to record it. Type several keys to press them one after another, each with the modifiers above.")
            .font(.caption).foregroundStyle(.secondary)
            .onAppear(perform: load)
            .onChange(of: slot.id) { _, _ in load() }
    }

    private func load() {
        let keys = slot.keySequence
        modifiers = keys?.modifiers ?? []
        text = keys?.text ?? ""
        unknown = []
    }

    /// While the key field has focus, a key pressed with ⌘, ⌥ or ⌃ is recorded: its
    /// modifiers set the toggles and the key is added to the field. ToolHUD's own shortcut
    /// is paused meanwhile, so it can be recorded too; another app's global shortcut still
    /// reaches that app first.
    private func startRecording() {
        guard recorder == nil else { return }
        HotKeyCenter.shared.pause()
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let key = Shortcut(event: event, requireModifier: true) else { return event }
            modifiers = key.modifiers
            text += KeySequence.token(for: key.key)
            save()
            return nil
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        NSEvent.removeMonitor(recorder)
        self.recorder = nil
        HotKeyCenter.shared.resume()
    }

    private func save() {
        let parsed = KeySequence.parse(text, modifiers: modifiers, lookup: KeyboardLayout.key(for:))
        unknown = parsed.unknown
        // Showing a button saved as one shortcut reads back the same keys; leave it alone
        // until something actually changes.
        guard parsed.sequence != slot.keySequence else { return }
        slot.keys = parsed.sequence
    }
}

/// A grid of symbols that suit buttons, with a search field for any other SF Symbol.
struct SymbolPicker: View {
    @Binding var symbol: String
    let color: Color
    let done: () -> Void
    @State private var search = ""

    private static let common = [
        "text.viewfinder", "qrcode.viewfinder", "translate", "captions.bubble", "eye", "clock.arrow.circlepath",
        "arrow.clockwise", "circle.dashed.inset.filled", "cursorarrow.click.2", "keyboard", "rectangle.dashed",
        "arrow.up.right", "list.clipboard", "square.stack.3d.up", "doc.on.clipboard", "text.badge.plus",
        "internaldrive", "house", "camera.viewfinder", "magnifyingglass", "pencil.and.outline", "highlighter",
        "scissors", "paintbrush", "wand.and.stars", "sparkles", "bolt", "star", "heart", "bookmark", "tag",
        "folder", "doc.text", "envelope", "paperplane", "bubble.left", "phone", "video", "mic", "speaker.wave.2",
        "play", "pause", "forward", "backward", "music.note", "photo", "film", "globe", "safari", "link",
        "lock", "key", "gear", "slider.horizontal.3", "power", "moon", "sun.max", "display", "macwindow",
        "rectangle.split.2x1", "square.grid.2x2", "terminal", "chevron.left.forwardslash.chevron.right",
        "hammer", "wrench.and.screwdriver", "trash", "arrow.down.circle", "arrow.up.circle", "plus.circle",
        "checkmark.circle", "xmark.circle", "questionmark.circle", "exclamationmark.triangle", "flag", "bell",
        "calendar", "timer", "stopwatch", "location", "map", "cart", "creditcard", "person", "person.2",
    ]

    var body: some View {
        VStack(spacing: 10) {
            TextField("", text: $search, prompt: Text("Any SF Symbol name"))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if NSImage(systemSymbolName: search, accessibilityDescription: nil) != nil { symbol = search; done() }
                }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                    ForEach(filtered, id: \.self) { name in
                        Button { symbol = name; done() } label: {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .foregroundStyle(symbol == name ? Color.white : color)
                                .frame(width: 36, height: 36)
                                .background(symbol == name ? color : Color.secondary.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 260)
        }
        .padding(12)
        .frame(width: 340)
    }

    private var filtered: [String] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return Self.common }
        let matches = Self.common.filter { $0.contains(term) }
        let exact = NSImage(systemSymbolName: term, accessibilityDescription: nil) != nil && !matches.contains(term) ? [term] : []
        return exact + matches
    }
}

// MARK: - Triggers

struct TriggersSettings: View {
    @State private var prefs = Preferences.shared
    @State private var hotKeys = HotKeyCenter.shared
    @State private var access = AccessibilityTrust.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Show HUD") {
                    ShortcutRecorder(shortcut: $prefs.hotKey)
                }
                if let warning = ShortcutConflicts.warning(for: prefs.hotKey) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                Text("Press the shortcut to open the HUD, then click a button. Press it again, or Esc, to close the HUD.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("In the HUD, the number keys run buttons 1 to 9 and 0 runs button 10. The button pad runs on A, S, D, F, G, H, J and K. The arrow keys and Tab move between buttons, Return runs the lit one, and Esc closes the HUD. With them on in Features, / searches and Space with no button lit runs the last action again.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Open with", selection: $prefs.mouseTrigger) {
                    ForEach(MouseTrigger.allCases, id: \.self) { trigger in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trigger.title)
                            Text(trigger.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(trigger)
                    }
                }
                .pickerStyle(.radioGroup)
                if prefs.mouseTrigger == .holdRight {
                    ValueSlider(title: "Hold for", value: $prefs.holdDelay, range: 0.15...0.8, step: 0.05,
                                format: { "\(Int(($0 * 1000).rounded())) ms" })
                }
            } header: {
                Text("Mouse")
            } footer: {
                Text("Works in every app. The HUD opens around the pointer and stays open when you let go; click a button to run it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Double-tap", selection: $prefs.doubleTapKey) {
                    ForEach(DoubleTapKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Screen corner", selection: $prefs.hotCorner) {
                    ForEach(HotCorner.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if prefs.hotCorner != .off {
                    ValueSlider(title: "Rest for", value: $prefs.cornerDelay, range: 0...1.5, step: 0.05,
                                format: { "\(Int(($0 * 1000).rounded())) ms" })
                }
            } header: {
                Text("More ways to open the HUD")
            } footer: {
                Text("Double-tap: press the key twice quickly on its own; holding it for a shortcut never counts. Screen corner: push the pointer into the corner and rest there. If macOS uses that corner for a Hot Corner too, both happen. Shortcuts and scripts can open toolhud://show, toolhud://show?ring=Safari (an app's ring or a folder, by name) and toolhud://repeat.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if access.isTrusted {
                    Label("ToolHUD has Accessibility access.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Mouse triggers, double-tap, keystrokes, typed text and menu items need Accessibility access. Lens actions and the keyboard shortcut work without it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Privacy Settings") {
                        access.request()
                        access.openSettings()
                    }
                }
            } header: {
                Text("Permission")
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.mouseTrigger) { _, _ in MouseTriggers.shared.apply() }
        .onChange(of: prefs.hotKey) { _, _ in HotKeyCenter.shared.apply() }
        .onChange(of: prefs.doubleTapKey) { _, _ in ExtraTriggers.shared.apply() }
        .onChange(of: prefs.hotCorner) { _, _ in ExtraTriggers.shared.apply() }
    }
}
