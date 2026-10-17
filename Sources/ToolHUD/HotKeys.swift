import AppKit
import Carbon.HIToolbox
import SwiftUI
import ToolHUDKit

extension Shortcut {
    /// Builds one from a key press. With `requireModifier`, only if it has at least one of
    /// ⌘ ⌥ ⌃: a bare key as a global shortcut would steal ordinary typing from every app.
    init?(event: NSEvent, requireModifier: Bool) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if requireModifier, flags.intersection([.command, .option, .control]).isEmpty { return nil }
        self.init(keyCode: event.keyCode, modifiers: Self.modifiers(flags),
                  key: KeyNames.name(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        return m
    }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    /// For showing the shortcut beside a menu item.
    var menuKeyEquivalent: (key: String, mask: NSEvent.ModifierFlags) {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.command) { mask.insert(.command) }
        let menuKey = keyCode == KeyCode.space ? " " : key.lowercased()
        return (menuKey.count == 1 ? menuKey : "", mask)
    }
}

/// The shortcut that opens the HUD, through Carbon's RegisterEventHotKey: works from a
/// menu bar app and needs no permission. Carbon also reports the release, which the Hold
/// mode runs on.
@Observable
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    @ObservationIgnored var onPress: (() -> Void)?
    @ObservationIgnored var onRelease: (() -> Void)?
    /// The shortcut couldn't be registered, almost always because another app holds it.
    private(set) var registrationFailed = false

    @ObservationIgnored private var ref: EventHotKeyRef?
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var paused = false

    /// Registers the shortcut in Preferences, replacing an earlier registration.
    func apply() {
        installHandlerOnce()
        unregister()
        guard !paused, let key = Preferences.shared.hotKey else {
            registrationFailed = false
            return
        }
        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x544F_4F4C), id: 1) // "TOOL"
        let status = RegisterEventHotKey(UInt32(key.keyCode), key.carbonModifiers, id, GetApplicationEventTarget(), 0, &newRef)
        if status == noErr, let newRef {
            ref = newRef
            registrationFailed = false
        } else {
            registrationFailed = true
            NSLog("ToolHUD: shortcut \(key.display) not registered (\(status)), probably taken by another app")
        }
    }

    /// While a shortcut is being recorded, the current one must not fire.
    func pause() {
        paused = true
        unregister()
    }

    func resume() {
        paused = false
        apply()
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 2, &specs, nil, nil)
    }

    fileprivate func fire(pressed: Bool) {
        if pressed { onPress?() } else { onRelease?() }
    }
}

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    // Carbon delivers hot keys on the main thread's event loop.
    MainActor.assumeIsolated { HotKeyCenter.shared.fire(pressed: pressed) }
    return noErr
}

/// Why a shortcut is a poor choice for opening the HUD, if it is.
@MainActor
enum ShortcutConflicts {
    static func warning(for shortcut: Shortcut?) -> String? {
        guard let shortcut else { return nil }
        if let purpose = SystemShortcuts.purpose(of: shortcut) {
            return "\(shortcut.display) is the macOS shortcut for \(purpose). Pick another one."
        }
        if let owner = LensCatalog.owner(of: shortcut, in: LensDirectory.shared.apps) {
            return "\(shortcut.display) is \(owner.app.name)'s shortcut for \(owner.feature.title). Pick another one, or change it in \(owner.app.name)."
        }
        if HotKeyCenter.shared.registrationFailed, Preferences.shared.hotKey == shortcut {
            return "Another app is already using \(shortcut.display), so ToolHUD can't. Pick another shortcut, or change it in that app."
        }
        return nil
    }
}

/// Click, then press a shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    /// A global shortcut needs ⌘, ⌥ or ⌃; a keystroke for a button may be any key.
    var requireModifier = true
    var placeholder = "Click to set"

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        update(view)
        return view
    }

    func updateNSView(_ view: RecorderButton, context: Context) { update(view) }

    private func update(_ view: RecorderButton) {
        view.onChange = { shortcut = $0 }
        view.requireModifier = requireModifier
        view.placeholder = placeholder
        view.shortcut = shortcut
    }

    final class RecorderButton: NSButton {
        var onChange: ((Shortcut?) -> Void)?
        var requireModifier = true
        var placeholder = "Click to set" { didSet { refresh() } }
        var shortcut: Shortcut? { didSet { refresh() } }
        private var recording = false { didSet { refresh() } }
        private var monitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            target = self
            action = #selector(toggle)
            refresh()
        }

        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: super.intrinsicContentSize.height) }

        private func refresh() {
            title = recording ? "Press keys…" : (shortcut?.display ?? placeholder)
        }

        @objc private func toggle() {
            recording ? stop() : start()
        }

        private func start() {
            recording = true
            HotKeyCenter.shared.pause()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let bare = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                switch Int(event.keyCode) {
                case kVK_Escape where bare:
                    self.stop()
                case kVK_Delete where bare, kVK_ForwardDelete where bare:
                    self.shortcut = nil
                    self.onChange?(nil)
                    self.stop()
                default:
                    guard let key = Shortcut(event: event, requireModifier: self.requireModifier) else {
                        NSSound.beep()
                        return nil
                    }
                    self.shortcut = key
                    self.onChange?(key)
                    self.stop()
                }
                return nil
            }
        }

        private func stop() {
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            // The binding writes Preferences synchronously, so this registers the new key.
            HotKeyCenter.shared.resume()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, recording { stop() }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
