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

    /// Builds one from a key code and Carbon modifiers (ShortcutsLens's Change Shortcut), named
    /// the way a key press would be in the current keyboard layout. Nil without ⌘ ⌥ or ⌃ (F-keys
    /// may stand alone), as the Settings editor would refuse it for the HUD shortcut.
    init?(keyCode: Int, carbonModifiers: Int) {
        guard (0...127).contains(keyCode) else { return nil }
        var m: KeyModifiers = []
        if carbonModifiers & controlKey != 0 { m.insert(.control) }
        if carbonModifiers & optionKey != 0 { m.insert(.option) }
        if carbonModifiers & shiftKey != 0 { m.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { m.insert(.command) }
        let code = UInt16(keyCode)
        guard !m.intersection([.control, .option, .command]).isEmpty || KeyNames.isFunctionKey(code) else { return nil }
        self.init(keyCode: code, modifiers: m)
    }

    /// The key with these modifiers, named as the current keyboard layout types it.
    init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.init(keyCode: keyCode, modifiers: modifiers,
                  key: KeyNames.name(keyCode: keyCode, characters: Self.layoutCharacter(keyCode)))
    }

    /// What the key types with no modifiers in the current layout ("h" for kVK_ANSI_H on QWERTY).
    static func layoutCharacter(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
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
        defer { if !paused { ShortcutsLensReport.publish() } }
        #if DEBUG
        // The shortcut editor test runs beside the real ToolHUD: it must not take its keys.
        if DebugHooks.blockHotKeys { registrationFailed = false; return }
        #endif
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

    /// For ShortcutsLens: the HUD shortcut while it's registered. The keys buttons send
    /// aren't ToolHUD's shortcuts, so they're left out.
    var reportedShortcuts: [ShortcutsLensReport.Shortcut] {
        guard ref != nil, let key = Preferences.shared.hotKey else { return [] }
        return [.init(id: "hotKey", title: "Show HUD", keyCode: Int(key.keyCode), carbonModifiers: Int(key.carbonModifiers))]
    }

    /// ShortcutsLens's Change Shortcut: saves the keys as the Settings editor does (so Settings
    /// and the menu show them and sync carries them) and registers again. Nil when done, or why not.
    func change(id: String, keyCode: Int, carbonModifiers: Int) -> String? {
        guard id == "hotKey" else { return "ToolHUD has no shortcut called \(id)." }
        guard let key = Shortcut(keyCode: keyCode, carbonModifiers: carbonModifiers) else {
            return "The Show HUD shortcut needs ⌘, ⌥ or ⌃ (F-keys may stand alone)."
        }
        if let purpose = SystemShortcuts.purpose(of: key) {
            return "\(key.display) is the macOS shortcut for \(purpose)."
        }
        let prefs = Preferences.shared
        let previous = prefs.hotKey
        prefs.hotKey = key
        apply()
        guard registrationFailed else { return nil }
        // Taken by another app: keep the old keys rather than leave the HUD without a shortcut.
        prefs.hotKey = previous
        apply()
        return "\(key.display) is taken by another app, so ToolHUD kept \(previous?.display ?? "no shortcut")."
    }

    /// Starts answering ShortcutsLens, Change Shortcut included.
    func startShortcutsLensReport() {
        ShortcutsLensReport.start({ HotKeyCenter.shared.reportedShortcuts }, change: { id, keyCode, modifiers in
            HotKeyCenter.shared.change(id: id, keyCode: keyCode, carbonModifiers: modifiers)
        })
    }

    /// While a shortcut is being set, the current one (and a double-tapped modifier) must not
    /// open the HUD.
    func pause() {
        paused = true
        ExtraTriggers.shared.suspended = true
        unregister()
    }

    func resume() {
        paused = false
        ExtraTriggers.shared.suspended = false
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
