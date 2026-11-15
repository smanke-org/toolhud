import AppKit
import Carbon.HIToolbox
import SwiftUI
import ToolHUDKit

/// The HUD shortcut's box. Clicking it opens an editor with modifier buttons and a key field;
/// pressing the keys while it's open fills them in too.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        // Keep its own width rather than stretching across a row.
        view.setContentHuggingPriority(.required, for: .horizontal)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onChange = { shortcut = $0 }
        view.shortcut = shortcut
    }

    final class RecorderButton: NSButton {
        var onChange: ((Shortcut?) -> Void)?
        var shortcut: Shortcut? { didSet { refresh() } }
        private var popover: NSPopover?
        private var model: ShortcutEditorModel?
        private var monitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            target = self
            action = #selector(open)
            refresh()
        }

        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: super.intrinsicContentSize.height) }

        private func refresh() {
            title = popover != nil ? "Set a shortcut…" : (shortcut?.display ?? "Click to set")
        }

        @objc private func open() {
            guard popover == nil, window != nil else { popover?.close(); return }
            // The current shortcut must not open the HUD while new keys are pressed.
            HotKeyCenter.shared.pause()
            let model = ShortcutEditorModel(shortcut: shortcut)
            model.finish = { [weak self] result in self?.finish(result) }
            self.model = model
            let host = NSHostingController(rootView: ShortcutEditor(model: model))
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = host
            popover.contentSize = host.view.fittingSize
            popover.delegate = PopoverCloser.shared
            PopoverCloser.shared.onClose[ObjectIdentifier(popover)] = { [weak self] in self?.closed() }
            self.popover = popover
            refresh()
            popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak model] event in
                guard let model else { return event }
                return model.handle(event) ? nil : event
            }
        }

        private func finish(_ result: ShortcutEditorModel.Result) {
            if case .set(let key) = result {
                shortcut = key
                onChange?(key)
            }
            popover?.close()
        }

        private func closed() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let popover { PopoverCloser.shared.onClose[ObjectIdentifier(popover)] = nil }
            popover = nil
            model = nil
            refresh()
            // The binding writes Preferences synchronously, so this registers the new keys.
            HotKeyCenter.shared.resume()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { popover?.close() }
            super.viewWillMove(toWindow: newWindow)
        }

        #if DEBUG
        var debugTitle: String { title }
        var debugModel: ShortcutEditorModel? { model }
        var debugPopoverView: NSView? { popover?.contentViewController?.view }
        var debugIsOpen: Bool { popover != nil }
        #endif
    }
}

/// NSPopover's delegate is weak; one shared object tells each box its popover closed.
@MainActor private final class PopoverCloser: NSObject, NSPopoverDelegate {
    static let shared = PopoverCloser()
    var onClose: [ObjectIdentifier: () -> Void] = [:]
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        onClose[ObjectIdentifier(popover)]?()
    }
}

@MainActor final class ShortcutEditorModel: ObservableObject {
    enum Result { case set(Shortcut?), cancel }

    @Published var control = false
    @Published var option = false
    @Published var shift = false
    @Published var command = false
    /// What's in the key box: one typed character, or a named key from the menu.
    @Published var keyText = ""
    /// Set when the key is known: typed, picked from the menu or pressed.
    @Published var keyCode: UInt16?
    @Published var showHint = false

    let original: Shortcut?
    var finish: ((Result) -> Void)?
    private var modifiersDown = false
    private var sawKey = false

    init(shortcut: Shortcut?) {
        original = shortcut
        if let shortcut {
            control = shortcut.modifiers.contains(.control)
            option = shortcut.modifiers.contains(.option)
            shift = shortcut.modifiers.contains(.shift)
            command = shortcut.modifiers.contains(.command)
            keyCode = shortcut.keyCode
            keyText = EditorKeys.name(shortcut.keyCode)
        }
    }

    var modifiers: KeyModifiers {
        var m: KeyModifiers = []
        if control { m.insert(.control) }
        if option { m.insert(.option) }
        if shift { m.insert(.shift) }
        if command { m.insert(.command) }
        return m
    }

    var combo: Shortcut? {
        guard let keyCode else { return nil }
        return Shortcut(keyCode: keyCode, modifiers: modifiers)
    }

    /// Why Set is off, when a key is chosen.
    var problem: String? {
        guard !keyText.isEmpty else { return nil }
        guard let keyCode else { return "No key on this keyboard types “\(keyText)”." }
        if !KeyNames.isFunctionKey(keyCode) && !(control || option || command) {
            return "Add ⌃, ⌥ or ⌘. Only F-keys can be used on their own."
        }
        return nil
    }

    /// A warning, not a block: macOS or one of your apps already uses these keys.
    var takenBy: String? {
        guard let combo, problem == nil else { return nil }
        if let purpose = SystemShortcuts.purpose(of: combo) {
            return "macOS uses this for \(purpose). It may not reach ToolHUD."
        }
        if let owner = LensCatalog.owner(of: combo, in: LensDirectory.shared.apps) {
            return "\(owner.app.name) uses this for \(owner.feature.title). Only one of them will get it."
        }
        return nil
    }

    /// The key box changed: keep the last character typed and find its key.
    func typed(_ text: String) {
        // The box handing back the name it shows ("Space", "F5") changes nothing.
        if let keyCode, EditorKeys.name(keyCode) == text { keyText = text; return }
        // Deleting from a key's name clears it; typing after it keeps the new character.
        if text.count > 1 {
            if keyText.hasPrefix(text) { keyText = ""; keyCode = nil }
            else if let last = text.last { typed(String(last)) }
            return
        }
        keyText = text
        guard let character = text.first else { keyCode = nil; return }
        if let (code, needsShift) = EditorKeys.keyCode(for: character) {
            keyCode = code
            if needsShift { shift = true }
            // Show the key itself: ⇧ + = stays “=”, not “+”.
            let base = EditorKeys.name(code)
            if base != text { keyText = base }
        } else {
            keyCode = nil
        }
    }

    func choose(_ code: UInt16) {
        keyCode = code
        keyText = EditorKeys.name(code)
    }

    /// A key press while the editor is open. True when it was used.
    func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .flagsChanged {
            // A shortcut another app has taken never arrives: the modifiers go down and up
            // with no key between them.
            let held = !flags.intersection([.command, .option, .control]).isEmpty
            if held && !modifiersDown { modifiersDown = true; sawKey = false }
            else if !held && modifiersDown { modifiersDown = false; if !sawKey { showHint = true } }
            return false
        }
        sawKey = true
        let code = event.keyCode
        if code == KeyCode.escape { finish?(.cancel); return true }
        if code == KeyCode.returnKey || code == KeyCode.keypadEnter, flags.isEmpty {
            if combo != nil && problem == nil { finish?(.set(combo)) }
            return true
        }
        // With ⌃ ⌥ or ⌘ held, or an F-key, it's the whole shortcut; plain typing goes to the key box.
        guard !flags.intersection([.command, .option, .control]).isEmpty || KeyNames.isFunctionKey(code) else { return false }
        control = flags.contains(.control)
        option = flags.contains(.option)
        shift = flags.contains(.shift)
        command = flags.contains(.command)
        choose(code)
        showHint = false
        return true
    }
}

struct ShortcutEditor: View {
    @ObservedObject var model: ShortcutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                toggle("⌃", "Control", $model.control)
                toggle("⌥", "Option", $model.option)
                toggle("⇧", "Shift", $model.shift)
                toggle("⌘", "Command", $model.command)
                Text("+").foregroundStyle(.secondary)
                TextField("Key", text: Binding(get: { model.keyText }, set: { model.typed($0) }))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .help("Type a letter, number or symbol")
                Menu {
                    ForEach(EditorKeys.specialKeys, id: \.self) { code in
                        Button(EditorKeys.spoken(code)) { model.choose(code) }
                    }
                    Divider()
                    ForEach(Array(KeyNames.functionKeyCodes.prefix(12)), id: \.self) { code in
                        Button(EditorKeys.name(code)) { model.choose(code) }
                    }
                    Menu("More F-keys") {
                        ForEach(Array(KeyNames.functionKeyCodes.dropFirst(12)), id: \.self) { code in
                            Button(EditorKeys.name(code)) { model.choose(code) }
                        }
                    }
                } label: { Image(systemName: "keyboard") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Keys you can't type: arrows, Space, Return, F-keys…")
            }

            Text(model.combo?.display ?? "No shortcut")
                .font(.title2.monospaced())
                .frame(maxWidth: .infinity)
                .foregroundStyle(model.combo == nil ? .secondary : .primary)

            if let problem = model.problem {
                note(problem, "exclamationmark.triangle")
            } else if let taken = model.takenBy {
                note(taken, "exclamationmark.triangle")
            }
            if model.showHint {
                note("Nothing came through. If you pressed a shortcut, another app is using those keys. Press different keys, or set them with the buttons above.", "info.circle")
            }
            Text("Or press the shortcut now.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("Clear") { model.finish?(.set(nil)) }
                    .disabled(model.original == nil)
                Spacer()
                Button("Cancel") { model.finish?(.cancel) }
                Button("Set") { model.finish?(.set(model.combo)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.combo == nil || model.problem != nil)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func toggle(_ symbol: String, _ name: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            Text(symbol).font(.title3).frame(minWidth: 22)
        }
        .toggleStyle(.button)
        .controlSize(.large)
        .help(name)
        .accessibilityLabel(name)
    }

    private func note(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Key names and lookups for the editor.
enum EditorKeys {
    static let specialKeys: [UInt16] = [KeyCode.space, KeyCode.returnKey, KeyCode.tab, KeyCode.escape,
                                        KeyCode.delete, KeyCode.forwardDelete,
                                        KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down,
                                        UInt16(kVK_Home), UInt16(kVK_End), UInt16(kVK_PageUp), UInt16(kVK_PageDown)]

    static func name(_ code: UInt16) -> String {
        KeyNames.name(keyCode: code, characters: Shortcut.layoutCharacter(code))
    }

    static func spoken(_ code: UInt16) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return ↩"
        case kVK_Tab: return "Tab ⇥"
        case kVK_Escape: return "Escape ⎋"
        case kVK_Delete: return "Delete ⌫"
        case kVK_ForwardDelete: return "Forward Delete ⌦"
        case kVK_LeftArrow: return "Left Arrow ←"
        case kVK_RightArrow: return "Right Arrow →"
        case kVK_UpArrow: return "Up Arrow ↑"
        case kVK_DownArrow: return "Down Arrow ↓"
        case kVK_Home: return "Home ↖"
        case kVK_End: return "End ↘"
        case kVK_PageUp: return "Page Up ⇞"
        case kVK_PageDown: return "Page Down ⇟"
        default: return name(code)
        }
    }

    /// The key that types this character in the current layout, and whether it needs ⇧:
    /// "k" and "K" are the K key on its own, "+" is ⇧ + "=" on US English.
    static func keyCode(for character: Character) -> (UInt16, Bool)? {
        if character == " " { return (KeyCode.space, false) }
        let lower = Character(String(character).lowercased())
        if let hit = KeyboardLayout.key(for: lower), !hit.shift { return (hit.keyCode, false) }
        if let hit = KeyboardLayout.key(for: character) { return (hit.keyCode, hit.shift) }
        return nil
    }
}
