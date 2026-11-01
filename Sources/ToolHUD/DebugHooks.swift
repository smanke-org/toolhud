#if DEBUG
import AppKit
import ToolHUDKit

/// Debug-only staging for the website's screenshots. A Debug build shares the installed
/// app's preferences, so these hooks only show things and never sync, update or save.
///
///   TOOLHUD_DEBUG_HUD=halo:0           opens that look with button 0 lit
///                                      (TOOLHUD_DEBUG_DELAY=<seconds> waits first, so another app can come forward)
///   TOOLHUD_DEBUG_PAD=right:6          shows the button pad there with that many buttons;
///                                      button indexes past the ring's light pad buttons
///   TOOLHUD_DEBUG_SAMPLE_BUTTONS=1     shows the default ring and pad buttons instead of yours
///   TOOLHUD_DEBUG_SETTINGS=appearance  opens that Settings pane
///                                      (TOOLHUD_DEBUG_SNAPSHOT=<png path> saves it there, then quits)
///   TOOLHUD_DEBUG_ACTIVITY_REMOTES=<json file>  shows those Macs ([DeviceActivity]) in Settings › Activity;
///                                      pair with TOOLHUD_ACTIVITY_FILE for this Mac's counts
///                                      and TOOLHUD_DEBUG_DEVICE_NAME for this Mac's name
///   TOOLHUD_DEBUG_MISSING=<bundle id>    treats that lens app as not installed
///   TOOLHUD_DEBUG_DRY_RUN=1              traces the button instead of running it
///   TOOLHUD_DEBUG_HELP_TEST=<png path>   presses Help on every Settings pane, traces what opened,
///                                      renders Help (TOOLHUD_DEBUG_HELP_TOPIC) and Settings, then quits
///   TOOLHUD_DEBUG_BUTTON=<index>         starts Settings › Buttons on that button
///   TOOLHUD_DEBUG_KEYS=<code>:<mods>,…   with TOOLHUD_DEBUG_SETTINGS=buttons on a keystroke button: clears the key
///                                      field, sends each key to it (mods = NSEvent.ModifierFlags raw), traces the result
///   TOOLHUD_DEBUG_RUN_LENS=<bundle id>:<feature>  runs that lens action as a button would
///   TOOLHUD_DEBUG_POST_TEXT=ks TOOLHUD_DEBUG_POST_MODS=<raw> TOOLHUD_DEBUG_POST_ONLY_TO=<app name>
///                                      presses those keys, only if that app is in front
///   TOOLHUD_DEBUG_UPDATE_NOTES=<folder>  draws the update prompt, What's New and Settings to PNGs there,
///                                      writes report.txt, then quits (from a copy with its own bundle id)
///   TOOLHUD_DEBUG_QUIT_TEST=<return|cancel|quit|suppress|off>  quits as ⌘Q does, then answers the
///                                      question a second later: presses Return, clicks Cancel or Quit
///                                      (ticking "Don't ask again" first for `suppress`), or with `off`
///                                      turns the setting off first; traces what the question showed
///
/// Both open on the first Retina display, so the shots are taken at 2×.
@MainActor
enum DebugHooks {
    static var freezeHighlight = false
    /// The look `debugShow` asked for, used in place of the saved one.
    static var look: Visualization?

    /// Whether this is a staging run, which must not touch the keychain or sync.
    static var isStaging: Bool {
        ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("TOOLHUD_DEBUG_") && $0 != "TOOLHUD_DEBUG_TRACE" }
    }

    /// Other Macs' activity to show in Settings › Activity, read once from a JSON file.
    static let activityRemotes: [DeviceActivity]? = {
        guard let path = ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_ACTIVITY_REMOTES"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? DeviceActivity.decoder.decode([DeviceActivity].self, from: data)
    }()

    /// Shows the buttons a new install starts with, for screenshots that don't depend on
    /// the user's own.
    static var sampleButtons: Bool { ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_SAMPLE_BUTTONS"] != nil }

    /// A button pad to show whatever Settings say, without saving anything.
    static var pad: (position: PadPosition, count: Int)? {
        guard let spec = ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_PAD"] else { return nil }
        let parts = spec.split(separator: ":")
        guard let position = parts.first.flatMap({ PadPosition(rawValue: String($0)) }) else { return nil }
        let count = parts.count > 1 ? Int(parts[1]) ?? DefaultPad.defaultCount : DefaultPad.defaultCount
        return (position, min(max(count, DefaultPad.minCount), DefaultPad.maxCount))
    }

    /// A lens app to treat as not installed, to see how Settings shows a missing app.
    static var missingApp: String? { ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_MISSING"] }

    /// The button Settings › Buttons starts on (0-based).
    static var selectedButton: Int? { ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_BUTTON"].flatMap { Int($0) } }

    static func trace(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_TRACE"] else { return }
        let line = Data((s + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: line)
        }
    }

    /// Waits for the keystroke editor's key field to get focus (focus it with accessibility),
    /// then sends each key in turn to it, clearing it first, and traces what the field and
    /// the button then hold.
    static func typeIntoKeyField(_ spec: String, window: NSWindow) {
        trace("waiting for key field focus")
        let deadline = Date().addingTimeInterval(30)
        while !(window.firstResponder is NSTextView), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        guard let editor = window.firstResponder as? NSTextView else { trace("no focus"); return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        for item in spec.split(separator: ",") {
            let parts = item.split(separator: ":").compactMap { UInt($0) }
            guard parts.count == 2 else { continue }
            editor.selectAll(nil)
            editor.insertText("", replacementRange: editor.selectedRange())
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let flags = NSEvent.ModifierFlags(rawValue: parts[1])
            let chars = parts[0] == 49 ? " " : (parts[0] == 40 ? "k" : "")
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                                                windowNumber: window.windowNumber, context: nil, characters: chars,
                                                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(parts[0])) {
                    NSApp.sendEvent(event)
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let slot = Preferences.shared.slots.first
            trace("keys \(item): key=\(window.isKeyWindow) field=\"\(editor.string)\" presses=\(slot?.keySequence?.display ?? "-")")
        }
    }

    static var screen: NSScreen? {
        NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? NSScreen.main
    }

    /// The menu hub acts as if it were hosting, so a staging run can read the guest apps'
    /// menus (read-only) while the installed ToolHUD holds the real port.
    static var pretendHosting: Bool { ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_PRETEND_HOSTING"] != nil }

    /// Starts a staging run if one was asked for; returns whether it did.
    static func run() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if let folder = env["TOOLHUD_DEBUG_UPDATE_NOTES"] {
            let start = Timer(timeInterval: 1, repeats: false) { _ in
                MainActor.assumeIsolated { DebugUpdateNotes.run(folder: folder) }
            }
            RunLoop.main.add(start, forMode: .common)
            return true
        }
        if let scenario = env["TOOLHUD_DEBUG_SCENARIO"] {
            // From a timer, not the main queue: blocks the HUD puts on the main queue then
            // still run while the scenario waits for them.
            let start = Timer(timeInterval: 1, repeats: false) { _ in
                MainActor.assumeIsolated { DebugScenarios.run(scenario) }
            }
            RunLoop.main.add(start, forMode: .common)
            return true
        }
        if let how = env["TOOLHUD_DEBUG_QUIT_TEST"] {
            trace("started policy \(NSApp.activationPolicy().rawValue) active \(NSApp.isActive)")
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(env["TOOLHUD_DEBUG_DELAY"] ?? "") ?? 1)) {
                MainActor.assumeIsolated {
                    if how == "off" { Preferences.shared.confirmQuit = false }
                    trace("quitting confirmQuit \(Preferences.shared.confirmQuit) policy \(NSApp.activationPolicy().rawValue) active \(NSApp.isActive)")
                    let answer = Timer(timeInterval: 1, repeats: false) { _ in
                        MainActor.assumeIsolated { answerQuitQuestion(how) }
                    }
                    RunLoop.main.add(answer, forMode: .common)
                    NSApp.terminate(nil)
                    // Only reached when the quit was called off.
                    let after = Timer(timeInterval: 0.5, repeats: false) { _ in
                        MainActor.assumeIsolated {
                            trace("still running; confirmQuit \(Preferences.shared.confirmQuit); policy \(NSApp.activationPolicy().rawValue) active \(NSApp.isActive)")
                        }
                    }
                    RunLoop.main.add(after, forMode: .common)
                }
            }
            return true
        }
        if let spec = env["TOOLHUD_DEBUG_HUD"] {
            let parts = spec.split(separator: ":")
            guard let look = parts.first.flatMap({ Visualization(rawValue: String($0)) }) else { return false }
            let index = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            let delay = Double(env["TOOLHUD_DEBUG_DELAY"] ?? "") ?? 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { HUDController.shared.debugShow(look, highlight: index) }
            }
            return true
        }
        if let spec = env["TOOLHUD_DEBUG_RUN_LENS"] {
            let parts = spec.split(separator: ":").map(String.init)
            guard parts.count == 2, let app = LensDirectory.shared.app(parts[0]) else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    let installed = LensDirectory.shared.installed[app.id]
                    trace("running \(spec) urls=\(installed?.supportsURLs ?? false) version=\(installed?.version ?? "none")")
                    ActionRunner.run(Slot(app, parts[1]))
                }
            }
            return true
        }
        if let text = env["TOOLHUD_DEBUG_POST_TEXT"], let target = env["TOOLHUD_DEBUG_POST_ONLY_TO"] {
            // Presses the keys, but only into the named app, so a stray run can't type into
            // whatever else is in front.
            let modifiers = KeyModifiers(rawValue: Int(env["TOOLHUD_DEBUG_POST_MODS"] ?? "") ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                MainActor.assumeIsolated {
                    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
                    guard front == target else { trace("not posted: \(front) is in front"); exit(2) }
                    let sequence = KeySequence.parse(text, modifiers: modifiers, lookup: KeyboardLayout.key(for:)).sequence
                    trace("posting \(sequence.display)")
                    ActionRunner.post(sequence)
                }
            }
            return true
        }
        if let snapshot = env["TOOLHUD_DEBUG_HELP_TEST"] {
            // Presses the Help button on every Settings pane, traces the topic it opened,
            // then renders the Help window to `snapshot` and quits.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    func helpButton(_ view: NSView) -> NSButton? {
                        if let b = view as? NSButton, b.bezelStyle == .helpButton, !b.isHiddenOrHasHiddenAncestor { return b }
                        for sub in view.subviews { if let hit = helpButton(sub) { return hit } }
                        return nil
                    }
                    // General hangs SwiftUI layout in a staging run (sync never started), so skip it.
                    for pane in SettingsPane.allCases where pane != .general {
                        SettingsWindow.shared.show(pane)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                        let button = SettingsWindow.shared.debugWindow?.contentView.flatMap(helpButton)
                        button?.performClick(nil)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                        trace("pane \(pane.rawValue): button=\(button != nil) opened=\(HelpWindow.shared.state.selection ?? "-") visible=\(HelpWindow.shared.window?.isVisible == true)")
                    }
                    let unresolved = Help.topics.filter { $0.blocks.contains { $0.searchText.contains("{") } }.map(\.id)
                    trace("topics=\(Help.topics.count) unresolved=\(unresolved) shortcut=\(Help.resolve("{shortcut}")) mouse=\(Help.resolve("{mouse}"))")
                    let menu = NSMenu()
                    (NSApp.delegate as? NSMenuDelegate)?.menuNeedsUpdate?(menu)
                    trace("menu: \(menu.items.map(\.title).filter { !$0.isEmpty })")
                    trace("help menu: \(NSApp.helpMenu?.items.map { $0.title + " " + $0.keyEquivalent } ?? [])")
                    HelpWindow.shared.show(topic: env["TOOLHUD_DEBUG_HELP_TOPIC"] ?? "using")
                    RunLoop.main.run(until: Date().addingTimeInterval(1))
                    if let view = HelpWindow.shared.window?.contentView?.superview,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot))
                    }
                    if let settings = SettingsWindow.shared.debugWindow, let view = settings.contentView?.superview,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot + ".settings.png"))
                    }
                    trace("done")
                    QuitConfirmation.quitNow()
                }
            }
            return true
        }
        if let name = env["TOOLHUD_DEBUG_SETTINGS"], let pane = SettingsPane(rawValue: name) {
            if env["TOOLHUD_DEBUG_DEMO_BUTTONS"] != nil { DebugScenarios.stageDemoButtons() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    // Opened on Appearance first (General hangs in a staging run), then switched.
                    SettingsWindow.shared.show(.appearance)
                    SettingsWindow.shared.show(pane)
                    if let window = SettingsWindow.shared.debugWindow,
                       let frame = screen?.visibleFrame {
                        window.setFrameAutosaveName("")
                        let size = NSSize(width: Double(env["TOOLHUD_DEBUG_WIDTH"] ?? "") ?? 960,
                                          height: Double(env["TOOLHUD_DEBUG_HEIGHT"] ?? "") ?? 760)
                        let target = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                            width: size.width, height: size.height)
                        window.setFrame(target, display: true)
                        // SwiftUI sizes the window again once the pane has laid out.
                        window.isRestorable = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            MainActor.assumeIsolated {
                                // The window server ignores moves of a window already on screen.
                                window.orderOut(nil)
                                window.setFrame(target, display: true)
                                window.makeKeyAndOrderFront(nil)
                                trace("moved to \(window.frame) number=\(window.windowNumber) visible=\(window.isVisible) screen=\(String(describing: window.screen?.localizedName))")
                                if let keys = env["TOOLHUD_DEBUG_KEYS"] { typeIntoKeyField(keys, window: window) }
                                guard let snapshot = env["TOOLHUD_DEBUG_SNAPSHOT"] else { return }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    MainActor.assumeIsolated {
                                        if let view = window.contentView?.superview,
                                           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                                            view.cacheDisplay(in: view.bounds, to: rep)
                                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshot))
                                        }
                                        trace("snapshot \(snapshot)")
                                        QuitConfirmation.quitNow()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
        return false
    }

    /// Answers the quit question for `TOOLHUD_DEBUG_QUIT_TEST`, tracing what it showed first.
    private static func answerQuitQuestion(_ how: String) {
        guard let window = NSApp.modalWindow else { trace("no question"); return }
        var texts: [String] = []
        var buttons: [NSButton] = []
        func walk(_ view: NSView) {
            if let button = view as? NSButton { buttons.append(button) }
            else if let field = view as? NSTextField, !field.stringValue.isEmpty { texts.append(field.stringValue) }
            view.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
        let titles = buttons.map { "\($0.title)[\($0.keyEquivalent == "\r" ? "Return" : $0.keyEquivalent == "\u{1b}" ? "Esc" : $0.keyEquivalent)]" }
        trace("asked \(texts) buttons \(titles) key \(window.isKeyWindow) visible \(window.isVisible) active \(NSApp.isActive) policy \(NSApp.activationPolicy().rawValue)")
        switch how {
        case "return":
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: "\r",
                                            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                NSApp.postEvent(event, atStart: false)
            }
            // Return should leave the question up; close it with Cancel afterwards.
            let check = Timer(timeInterval: 1, repeats: false) { _ in
                MainActor.assumeIsolated {
                    trace("after Return: question still up \(NSApp.modalWindow != nil)")
                    buttons.first { $0.title == "Cancel" }?.performClick(nil)
                }
            }
            RunLoop.main.add(check, forMode: .common)
        case "cancel": buttons.first { $0.title == "Cancel" }?.performClick(nil)
        case "quit", "suppress":
            if how == "suppress" { buttons.first { $0.title == "Don't ask again" }?.performClick(nil) }
            buttons.first { $0.title == "Quit" }?.performClick(nil)
        default: break
        }
    }
}
#endif
