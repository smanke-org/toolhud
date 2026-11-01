#if DEBUG
import AppKit
import ToolHUDKit

/// Debug-only walkthroughs of the 2.0 features, for `TOOLHUD_DEBUG_SCENARIO`. Settings are
/// changed in memory only (staging runs never save), and each step is traced.
///
///   hud      folders, search, repeat, rings for each app, lights and toolhud:// links,
///            with TOOLHUD_DEBUG_DRY_RUN=1 so nothing chosen actually runs.
///            TOOLHUD_DEBUG_SNAPSHOT_DIR=<dir> saves pictures of the HUD along the way.
///   kinds    runs each new kind of button for real: shell and AppleScript scripts and
///            steps write to TOOLHUD_DEBUG_OUT_DIR; text and a menu item go to the app
///            TOOLHUD_DEBUG_TARGET (a bundle identifier) names.
///   doubletap posts two quick ⌥ taps and traces whether the HUD opened.
@MainActor
enum DebugScenarios {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static func run(_ name: String) {
        // The real pointer mustn't light buttons or rows while the scenario drives the HUD.
        DebugHooks.freezeHighlight = true
        switch name {
        case "hud": hud()
        case "kinds": kinds()
        case "doubletap": doubleTap()
        case "statenote":
            FeatureStates.shared.requestRefresh()
            pump(4)
            DebugHooks.trace("states \(FeatureStates.shared.states)")
        default: DebugHooks.trace("no scenario \(name)")
        }
        DebugHooks.trace("done")
        QuitConfirmation.quitNow()
    }

    private static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func key(_ code: UInt16, _ characters: String = "") {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: code) else { return }
        HUDController.shared.key(event)
        pump(0.05)
    }

    private static func type(_ text: String) {
        for ch in text { key(0, String(ch)) }
    }

    private static func snapshot(_ name: String) {
        guard let dir = env["TOOLHUD_DEBUG_SNAPSHOT_DIR"], let view = HUDController.shared.debugPanel?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        DebugHooks.trace("snapshot \(name)")
    }

    private static func state(_ label: String) {
        let m = HUDController.shared.model
        DebugHooks.trace("\(label): showing=\(HUDController.shared.isShowing) folder=\(m.folderName ?? "-") levels=\(HUDController.shared.debugLevels) slots=\(m.slots.map(\.name)) searching=\(m.searching) hint=\(m.hint.map { "\($0.title)/\($0.app)" } ?? "-")")
    }

    // MARK: - The HUD

    private static func hud() {
        let prefs = Preferences.shared
        prefs.searchEnabled = true
        prefs.repeatLastEnabled = true
        prefs.foldersEnabled = true
        prefs.appMenuButtonsEnabled = true
        prefs.stateLightsEnabled = true
        prefs.appRingsEnabled = true
        prefs.visualization = .halo
        var slots = DefaultRing.slots
        slots[0] = Slot(name: "Tools", symbol: "folder", mode: .folder, children: [
            Slot(name: "Inner A", symbol: "a.circle", mode: .keystroke),
            Slot(name: "Inner B", symbol: "b.circle", mode: .script, script: "true", scriptKind: .shell),
            Slot(name: "Inner C", symbol: "c.circle", mode: .open, openTarget: "https://example.com"),
        ])
        prefs.slots = slots
        prefs.slotCount = 8
        let front = NSWorkspace.shared.frontmostApplication
        DebugHooks.trace("frontmost \(front?.bundleIdentifier ?? "-")")
        if let id = front?.bundleIdentifier {
            prefs.appRings = [AppRing(bundleID: id, name: front?.localizedName ?? "Front",
                                      slots: [Slot(name: "AR1", symbol: "1.circle", mode: .keystroke),
                                              Slot(name: "AR2", symbol: "2.circle", mode: .keystroke),
                                              Slot(name: "AR3", symbol: "3.circle", mode: .keystroke)],
                                      slotCount: 3, padSlots: [], padCount: 2)]
        }

        // A ring for the app in front.
        HUDController.shared.show(atScreenCenter: true)
        pump(0.5)
        state("app ring")
        HUDController.shared.dismiss()
        prefs.appRingsEnabled = false
        HUDController.shared.show(atScreenCenter: true)
        pump(0.5)
        state("rings for each app off")
        HUDController.shared.dismiss()
        prefs.appRingsEnabled = true

        // Folders.
        HUDController.shared.show(atScreenCenter: true, ring: .usual)
        pump(0.5)
        state("usual ring")
        key(KeyCode.digits[0], "1")
        pump(0.6)
        state("after 1 (folder)")
        snapshot("folder")
        key(KeyCode.escape)
        pump(0.3)
        state("after Esc")
        key(KeyCode.digits[0], "1")
        pump(0.3)
        key(KeyCode.delete)
        state("after Delete")

        // Search.
        key(0, "/")
        state("after /")
        DebugHooks.trace("empty search: \(HUDController.shared.model.results.map(\.title))")
        type("cap")
        pump(0.3)
        DebugHooks.trace("search cap: \(HUDController.shared.model.results.map { "\($0.title) [\($0.subtitle)]" })")
        snapshot("search")
        type("zzqx")
        DebugHooks.trace("search nonsense: \(HUDController.shared.model.results.count) results")
        for _ in 0..<4 { key(KeyCode.delete) }
        key(KeyCode.down)
        DebugHooks.trace("selected \(HUDController.shared.model.resultIndex)")
        // Shortcuts join a moment later.
        pump(2)
        let shortcuts = HUDController.shared.model.results.filter { $0.subtitle == "Shortcut" }.count
        DebugHooks.trace("shortcut results in top rows: \(shortcuts)")
        key(KeyCode.returnKey)
        pump(0.5)
        state("after Return")
        DebugHooks.trace("last action \(LastAction.slot?.name ?? "-")")

        // Clicking a result row.
        HUDController.shared.show(atScreenCenter: true, ring: .usual)
        pump(0.4)
        key(0, "/")
        type("tool")
        let row0 = SearchCardLayout.origin(rows: max(HUDController.shared.model.results.count, 1))
        DebugHooks.trace("search tool: \(HUDController.shared.model.results.map(\.title))")
        HUDController.shared.click(at: HUDPoint(row0.x + 40, row0.y + SearchCardLayout.fieldHeight + 10))
        pump(0.4)
        state("after clicking the Tools result")
        HUDController.shared.dismiss()

        // Running the last action again from the center.
        HUDController.shared.show(atScreenCenter: true, ring: .usual)
        pump(0.6)
        HUDController.shared.click(at: HUDPoint(0, 5))
        pump(0.5)
        state("after center click")
        HUDController.shared.show(atScreenCenter: true, ring: .usual)
        pump(0.4)
        key(KeyCode.space, " ")
        pump(0.5)
        state("after Space")

        // Lights.
        var lit = DefaultRing.slots
        lit[0] = slots[0]
        prefs.slots = lit
        HUDController.shared.show(atScreenCenter: true, ring: .usual)
        FeatureStates.shared.debugSet("com.smanke.ClickLens", ["spotlight": true, "clicks": false])
        FeatureStates.shared.debugSet("com.smanke.TextLens", ["capture": true])
        pump(0.8)
        DebugHooks.trace("lit: \(HUDController.shared.model.slots.map { FeatureStates.shared.isOn($0).map(String.init) ?? "-" })")
        snapshot("lights")
        HUDController.shared.dismiss()

        // Links.
        let delegate = NSApp.delegate as? AppDelegate
        for link in ["toolhud://show?ring=tools", "toolhud://show?ring=\(front?.localizedName ?? "x")", "toolhud://show?ring=nope"] {
            HUDController.shared.dismiss()
            delegate?.application(NSApp, open: [URL(string: link.replacingOccurrences(of: " ", with: "%20"))!])
            pump(0.6)
            state(link)
        }
        HUDController.shared.dismiss()

        // The guest apps' menus, read for search.
        let items = MenuHubHost.shared.searchableItems()
        DebugHooks.trace("menu items: \(items.count) from \(Set(items.map(\.appName)).sorted()); e.g. \(items.prefix(5).map { ([$0.appName] + $0.parents + [$0.title]).joined(separator: " › ") })")
    }

    // MARK: - Each kind, for real

    private static func kinds() {
        let out = env["TOOLHUD_DEBUG_OUT_DIR"] ?? NSTemporaryDirectory()
        func path(_ name: String) -> String { (out as NSString).appendingPathComponent(name) }
        DebugHooks.trace("accessibility \(AccessibilityTrust.shared.isTrusted)")

        ActionRunner.run(Slot(name: "Shell", symbol: "terminal", mode: .script, script: "echo shell-ok > '\(path("shell.txt"))'",
                              scriptKind: .shell))
        ActionRunner.run(Slot(name: "AS", symbol: "terminal", mode: .script,
                              script: "do shell script \"echo applescript-ok > '\(path("applescript.txt"))'\""))
        ActionRunner.run(Slot(name: "Bad", symbol: "terminal", mode: .script, script: "exit 3", scriptKind: .shell))
        ActionRunner.run(Slot(name: "Missing shortcut", symbol: "x", mode: .shortcut, shortcutName: "No Such Shortcut 7Q"))
        ActionRunner.run(Slot(name: "Steps", symbol: "list.number", mode: .chain, steps: [
            ChainStep(action: Slot(name: "s1", symbol: "x", mode: .script, script: "date +%s.%N >> '\(path("steps.txt"))'", scriptKind: .shell), delay: 1.0),
            ChainStep(action: Slot(name: "s2", symbol: "x", mode: .script, script: "date +%s.%N >> '\(path("steps.txt"))'", scriptKind: .shell), delay: 0),
        ]))
        ActionRunner.run(Slot(name: "Open missing", symbol: "x", mode: .open, openTarget: "/nonexistent/file.txt"))
        pump(3)

        guard let target = env["TOOLHUD_DEBUG_TARGET"],
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: target).first else {
            DebugHooks.trace("no target app")
            return
        }
        let name = app.localizedName ?? target
        // A guard of the test's own as well: give up unless the target can come forward.
        _ = name
        ActionRunner.run(Slot(name: "Type", symbol: "x", mode: .text, sendTo: .app(bundleID: target, name: name),
                              text: "Hello ToolHUD\nsecond line"))
        pump(2.5)
        ActionRunner.run(Slot(name: "Paste", symbol: "x", mode: .text, sendTo: .app(bundleID: target, name: name),
                              text: " pasted-é", textMethod: .paste))
        pump(2)
        ActionRunner.run(Slot(name: "Menu", symbol: "x", mode: .menuItem, sendTo: .app(bundleID: target, name: name),
                              menuPath: ["Test", "Mark Done..."]))
        pump(1.5)
        ActionRunner.run(Slot(name: "Menu missing", symbol: "x", mode: .menuItem, sendTo: .app(bundleID: target, name: name),
                              menuPath: ["Test", "Nothing Here"]))
        pump(1.5)
        DebugHooks.trace("menu paths in target: \(MenuPress.allPaths(in: app.processIdentifier).map(MenuPath.display))")
    }

    // MARK: - Settings pictures

    /// One button of each new kind, in memory, with every feature on, for pictures of
    /// Settings (`TOOLHUD_DEBUG_DEMO_BUTTONS`).
    static func stageDemoButtons() {
        let prefs = Preferences.shared
        prefs.searchEnabled = true
        prefs.foldersEnabled = true
        prefs.appMenuButtonsEnabled = true
        prefs.appRingsEnabled = true
        prefs.repeatLastEnabled = true
        prefs.doubleTapKey = .option
        prefs.hotCorner = .bottomLeft
        let c = LensCatalog.self
        var slots = DefaultRing.slots
        slots[0] = Slot(name: "Morning", symbol: "list.number", mode: .chain, steps: [
            ChainStep(action: Slot(c.textLens, "capture"), delay: 0.5),
            ChainStep(action: Slot(name: "Notes", symbol: "arrow.up.forward.app", mode: .open, openTarget: "/System/Applications/Notes.app"), delay: 1),
            ChainStep(action: Slot(name: "Paste", symbol: "keyboard", mode: .keystroke,
                                   keys: KeySequence(Shortcut(keyCode: KeyCode.v, modifiers: [.command], key: "V"))), delay: 0),
        ])
        slots[1] = Slot(name: "Sign-off", symbol: "character.cursor.ibeam", mode: .text, text: "Thanks,\nAlex", textMethod: .paste)
        slots[2] = Slot(name: "Export PDF", symbol: "filemenu.and.selection", mode: .menuItem, menuPath: ["File", "Export as PDF…"])
        slots[3] = Slot(name: "Dark mode", symbol: "terminal", mode: .script,
                        script: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        slots[4] = Slot(name: "Capture", symbol: "folder", mode: .folder,
                        children: [Slot(c.textLens, "capture"), Slot(c.textLens, "qr"), Slot(c.captureLens, "area")])
        slots[5] = Slot(name: "Clipboard", symbol: "menubar.rectangle", mode: .appMenu, menuApp: "com.smanke.PasteLens", menuAppName: "PasteLens")
        slots[6] = Slot(name: "Make GIF", symbol: "square.2.layers.3d", mode: .shortcut, shortcutName: "Make GIF")
        slots[7] = Slot(name: "Docs", symbol: "safari", mode: .open, openTarget: "https://developer.apple.com")
        prefs.slots = slots
        prefs.slotCount = 8
        prefs.appRings = [AppRing.copying(bundleID: "com.apple.Safari", name: "Safari", slots: DefaultRing.slots, slotCount: 6,
                                          padSlots: DefaultPad.slots, padCount: 4)]
    }

    // MARK: - Double-tap

    private static func doubleTap() {
        Preferences.shared.doubleTapKey = .option
        ExtraTriggers.shared.apply()
        pump(0.3)
        let source = CGEventSource(stateID: .hidSystemState)
        for flags in [CGEventFlags.maskAlternate, [], .maskAlternate, []] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 58, keyDown: !flags.isEmpty)
            event?.type = .flagsChanged
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            pump(0.06)
        }
        pump(0.5)
        DebugHooks.trace("after double ⌥: showing=\(HUDController.shared.isShowing)")
        HUDController.shared.dismiss()
        ExtraTriggers.shared.stop()
    }
}
#endif
