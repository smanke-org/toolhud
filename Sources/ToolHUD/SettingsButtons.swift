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

    enum ButtonList: String, CaseIterable {
        case ring, pad
        var title: String { rawValue.capitalized }
    }

    /// The pad's list, only while the pad is on.
    private var editingPad: Bool { list == .pad && prefs.padEnabled }
    private var count: Int { editingPad ? prefs.padCount : prefs.slotCount }
    private var limits: ClosedRange<Int> {
        editingPad ? DefaultPad.minCount...DefaultPad.maxCount : DefaultRing.minCount...DefaultRing.maxCount
    }
    private var index: Int { min(selection ?? 0, count - 1) }

    private var slot: Binding<Slot> {
        if editingPad {
            return Binding(get: { prefs.padSlots[index] }, set: { prefs.padSlots[index] = $0 })
        }
        return Binding(get: { prefs.slots[index] }, set: { prefs.slots[index] = $0 })
    }

    private func setCount(_ value: Int) {
        if editingPad { prefs.padCount = value } else { prefs.slotCount = value }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
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
                        ForEach(Array(prefs.visiblePadSlots.enumerated()), id: \.element.id) { i, item in
                            SlotRow(key: DefaultPad.keyLetters[i], slot: item).tag(i)
                        }
                        .onMove { from, to in prefs.padSlots.move(fromOffsets: from, toOffset: to) }
                    } else {
                        ForEach(Array(prefs.visibleSlots.enumerated()), id: \.element.id) { i, item in
                            SlotRow(key: "\(i + 1)", slot: item).tag(i)
                        }
                        .onMove { from, to in prefs.slots.move(fromOffsets: from, toOffset: to) }
                    }
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
                           if editingPad { prefs.padSlots[index] = DefaultPad.slots[index] } else { prefs.slots[index] = DefaultRing.slots[index] }
                       },
                       importRing: importRing, exportRing: exportRing, importError: importError)
        }
        .onChange(of: list) { _, _ in selection = 0 }
        .onChange(of: prefs.padEnabled) { _, on in if !on { list = .ring; selection = 0 } }
        #if DEBUG
        .onAppear { if let button = DebugHooks.selectedButton { selection = button } }
        #endif
    }

    private func exportRing() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "My ToolHUD ring.\(RingFile.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: RingFile.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let ring = RingFile(visualization: prefs.visualization, slots: prefs.visibleSlots,
                                pad: prefs.padEnabled ? prefs.visiblePadSlots : nil,
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
            prefs.adopt(try RingFile.decode(Data(contentsOf: url)))
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
                Text(slot.mode == .lens ? (slot.appName ?? "Lens action") : (slot.keySequence?.display ?? "Keystroke"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(key).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Everything about one button.
struct SlotEditor: View {
    @Binding var slot: Slot
    let title: String
    let reset: () -> Void
    let importRing: () -> Void
    let exportRing: () -> Void
    let importError: String?

    @State private var directory = LensDirectory.shared
    @State private var prefs = Preferences.shared
    @State private var choosingSymbol = false

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

            Section {
                Picker("When chosen", selection: $slot.mode) {
                    ForEach(ActionMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch slot.mode {
                case .lens: lensFields
                case .keystroke: keystrokeFields
                }
            } footer: {
                Text(slot.mode == .lens
                     ? "A lens action asks the app to run the feature directly, so it keeps working if you change the app's shortcuts."
                     : "A keystroke presses keys for you, as if you'd typed them. The HUD never takes focus, so they go to the app that was in front when it opened.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Test This Button") {
                        let toRun = slot
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            MainActor.assumeIsolated { ActionRunner.run(toRun) }
                        }
                    }
                    Button("Reset Button") { reset() }
                    Spacer()
                    Button("Import Ring…") { importRing() }
                    Button("Export Ring…") { exportRing() }
                }
                if let importError {
                    Text(importError).font(.callout).foregroundStyle(.red)
                }
            } footer: {
                Text("A ring file holds your buttons, the button pad and the HUD's look, to keep or to share with someone else.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        if previous == nil || slot.symbol == previous?.symbol || slot.symbol == "plus.circle" { slot.symbol = feature.symbol }
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
                Text("In the HUD, the number keys run buttons 1 to 9 and 0 runs button 10. The button pad runs on A, S, D, F, G, H, J and K. The arrow keys and Tab move between buttons, Return runs the lit one, and Esc closes the HUD.")
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
                if access.isTrusted {
                    Label("ToolHUD has Accessibility access.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Mouse triggers and keystroke buttons need Accessibility access. Lens actions and the keyboard shortcut work without it.",
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
    }
}
