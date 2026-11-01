import AppKit
import ApplicationServices
import Observation
import ToolHUDKit

/// Accessibility trust, which keystroke buttons and the mouse triggers need.
///
/// macOS sends no notification when it changes, so it's polled; the mouse triggers are set
/// up again when it does, because an event tap made before trust was granted never starts
/// receiving events.
@Observable
@MainActor
final class AccessibilityTrust {
    static let shared = AccessibilityTrust()

    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AccessibilityTrust.shared.check() }
        }
    }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func check() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        NSLog("ToolHUD: Accessibility trust is now \(trusted)")
        onChange?()
    }
}

/// Runs a button.
@MainActor
enum ActionRunner {
    /// Marks keystrokes ToolHUD posts, so its own event tap lets them through.
    nonisolated static let eventMarker: Int64 = 0x544F_4F4C // "TOOL"

    static func run(_ slot: Slot) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_DRY_RUN"] != nil {
            DebugHooks.trace("would run \(slot.name)")
            return
        }
        #endif
        switch slot.mode {
        case .lens: runLens(slot)
        case .keystroke: runKeystroke(slot)
        case .shortcut: runShortcut(slot)
        case .open: runOpen(slot)
        case .text: runText(slot)
        case .menuItem: runMenuItem(slot)
        case .script: runScript(slot)
        case .chain: runSteps(slot)
        case .folder: HUDController.shared.openFolder(slot)
        case .appMenu: runAppMenu(slot)
        }
    }

    // MARK: - Lens actions

    private static func runLens(_ slot: Slot) {
        let directory = LensDirectory.shared
        guard let id = slot.lensApp, let app = directory.app(id), let featureID = slot.lensFeature,
              let feature = app.feature(featureID) else {
            Toast.show("\(slot.name) has no action yet. Set one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        // Looked up again: the app may have been installed or updated since launch.
        if directory.installed[id] == nil { directory.refresh() }
        guard let installed = directory.installed[id] else {
            Toast.show("\(app.name) isn't installed.", symbol: "questionmark.app")
            return
        }

        if installed.supportsURLs, let url = app.url(for: featureID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = feature.activates
            NSWorkspace.shared.open([url], withApplicationAt: installed.url, configuration: configuration) { _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Toast.show("\(app.name) didn't respond: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
                    }
                }
            }
        } else if LensCatalog.isOpenOnly(featureID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: installed.url, configuration: configuration)
        } else if let shortcut = feature.shortcut {
            // An older version without lens actions: its own shortcut does the same thing,
            // as long as it hasn't been changed there.
            post(shortcut)
        } else {
            Toast.show("Update \(app.name) to use \(feature.title) from ToolHUD.", symbol: "arrow.down.app")
        }
    }

    // MARK: - Keystrokes

    private static func runKeystroke(_ slot: Slot) {
        guard let keys = slot.keySequence, !keys.keys.isEmpty else {
            Toast.show("\(slot.name) has no keystroke yet. Set one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        inTarget(slot.sendTo) { post(keys) }
    }

    /// Runs `work` in the app you were using, or brings the chosen app forward (opening it
    /// if need be) and runs it there. Keys and text are never sent unless that app really
    /// is in front, so they can't land in the wrong app.
    private static func inTarget(_ target: SendTarget, _ work: @escaping @MainActor () -> Void) {
        switch target {
        case .frontmost:
            work()
        case .app(let bundleID, let name):
            let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            guard let url else {
                Toast.show("\(name) isn't installed.", symbol: "questionmark.app")
                return
            }
            // Through Launch Services, as the Dock does: macOS 27 ignores activate() from an
            // app that isn't active itself, which ToolHUD never is while the HUD is up.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let error {
                            Toast.show("\(name) didn't open: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
                        } else {
                            whenInFront(bundleID, name: name, work)
                        }
                    }
                }
            }
        }
    }

    /// Runs `work` once the app is in front and has had a moment to settle, or says it
    /// didn't come forward.
    private static func whenInFront(_ bundleID: String, name: String, deadline: Date = Date().addingTimeInterval(3),
                                    _ work: @escaping @MainActor () -> Void) {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                MainActor.assumeIsolated {
                    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
                        Toast.show("\(name) didn't stay in front, so ToolHUD sent nothing.", symbol: "exclamationmark.triangle")
                        return
                    }
                    work()
                }
            }
        } else if Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated { whenInFront(bundleID, name: name, deadline: deadline, work) }
            }
        } else {
            Toast.show("\(name) didn't come to the front, so ToolHUD sent nothing.", symbol: "exclamationmark.triangle")
        }
    }

    // MARK: - Shortcuts, Open and Script

    private static func runShortcut(_ slot: Slot) {
        guard let name = slot.shortcutName, !name.isEmpty else {
            Toast.show("\(slot.name) has no shortcut yet. Choose one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        launch("/usr/bin/shortcuts", ["run", name], failure: "The shortcut “\(name)” didn't run")
    }

    private static func runOpen(_ slot: Slot) {
        guard let target = slot.openTarget?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty,
              let url = openURL(target) else {
            Toast.show("\(slot.name) has nothing to open yet. Choose something in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path) {
            Toast.show("\(url.lastPathComponent) isn't there any more.", symbol: "questionmark.folder")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// A web address as typed (https:// added when there's no scheme), or a path.
    static func openURL(_ target: String) -> URL? {
        if target.hasPrefix("/") || target.hasPrefix("~") {
            return URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        }
        if let url = URL(string: target), url.scheme != nil { return url }
        return URL(string: "https://" + target)
    }

    private static func runScript(_ slot: Slot) {
        guard let script = slot.script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Toast.show("\(slot.name) has no script yet. Write one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        switch slot.scriptKind {
        case .appleScript: launch("/usr/bin/osascript", ["-e", script], failure: "\(slot.name) stopped with an error")
        case .shell: launch("/bin/zsh", ["-l", "-c", script], failure: "\(slot.name) stopped with an error")
        }
    }

    /// Runs a command without waiting for it, and says so if it fails.
    private static func launch(_ path: String, _ arguments: [String], failure: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").first.map(String.init) ?? "exit code \(finished.terminationStatus)"
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Toast.show("\(failure): \(detail)", symbol: "exclamationmark.triangle") }
            }
        }
        do {
            try process.run()
        } catch {
            Toast.show("\(failure): \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
    }

    // MARK: - Steps

    private static func runSteps(_ slot: Slot) {
        let steps = (slot.steps ?? []).filter { $0.action.mode.canBeStep }
        guard !steps.isEmpty else {
            Toast.show("\(slot.name) has no steps yet. Add some in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        Task { @MainActor in
            for step in steps {
                run(step.action)
                if step.delay > 0 { try? await Task.sleep(for: .seconds(step.delay)) }
            }
        }
    }

    // MARK: - App menu

    private static func runAppMenu(_ slot: Slot) {
        guard Preferences.shared.appMenuButtonsEnabled else {
            Toast.show("App menu buttons are turned off. Turn them on in ToolHUD Settings › Features.", symbol: "menubar.rectangle")
            return
        }
        guard let id = slot.menuApp else {
            Toast.show("\(slot.name) has no app yet. Choose one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        let name = slot.menuAppName ?? "That app"
        if !MenuHubHost.shared.popUpMenu(for: id, title: name) {
            Toast.show("\(name)'s menu isn't in ToolHUD's menu right now. Open \(name), and keep “Gather my other apps’ menus here” on in ToolHUD Settings › General.",
                       symbol: "menubar.rectangle")
        }
    }

    // MARK: - Type text

    private static func runText(_ slot: Slot) {
        guard let text = slot.text, !text.isEmpty else {
            Toast.show("\(slot.name) has no text yet. Write it in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        guard requireAccessibility("type text") else { return }
        inTarget(slot.sendTo) {
            switch slot.textMethod {
            case .type: type(text)
            case .paste: paste(text)
            }
        }
    }

    /// Types the text as keyboard input, a few characters per event. Returns and tabs are
    /// pressed as keys, so they work in apps that ignore them as typed characters.
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        func send(_ chunk: [UniChar]) {
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
                event.post(tap: .cghidEventTap)
            }
            usleep(4_000)
        }
        var pending: [UniChar] = []
        func flush() {
            while !pending.isEmpty {
                send(Array(pending.prefix(16)))
                pending.removeFirst(min(16, pending.count))
            }
        }
        for ch in text {
            if ch == "\n" || ch == "\r\n" || ch == "\t" {
                flush()
                post(Shortcut(keyCode: ch == "\t" ? KeyCode.tab : KeyCode.returnKey, modifiers: [], key: ""))
                usleep(4_000)
            } else {
                pending.append(contentsOf: Array(String(ch).utf16))
            }
        }
        flush()
    }

    /// Pastes the text, then puts the clipboard back as it was. Marked transient, so
    /// clipboard history apps (PasteLens included) don't keep it.
    static func paste(_ text: String) {
        let board = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        board.setString(text, forType: .string)
        board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        post(Shortcut(keyCode: KeyCode.v, modifiers: [.command], key: "V"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            board.clearContents()
            let items = saved.map { types -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
    }

    // MARK: - Menu items

    private static func runMenuItem(_ slot: Slot) {
        guard let path = slot.menuPath, !path.isEmpty else {
            Toast.show("\(slot.name) has no menu item yet. Choose one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        guard requireAccessibility("choose menu items") else { return }
        inTarget(slot.sendTo) {
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let name = app.localizedName ?? "The app in front"
            switch MenuPress.press(path, in: app.processIdentifier) {
            case .done: break
            case .notFound(let missing):
                Toast.show("\(name) has no menu item “\(missing)” (looking for \(MenuPath.display(path))).", symbol: "filemenu.and.selection")
            case .disabled:
                Toast.show("\(MenuPath.display(path)) is dimmed in \(name) right now.", symbol: "filemenu.and.selection")
            }
        }
    }

    /// Asks for Accessibility when it's missing; false means stop.
    private static func requireAccessibility(_ what: String) -> Bool {
        guard !AccessibilityTrust.shared.isTrusted else { return true }
        AccessibilityTrust.shared.request()
        Toast.show("ToolHUD needs Accessibility access to \(what). Turn it on in System Settings › Privacy & Security.",
                   symbol: "hand.raised")
        return false
    }

    static func post(_ shortcut: Shortcut) { post(KeySequence(shortcut)) }

    /// Presses the keys in turn, each with the sequence's modifiers held, as if typed.
    /// Needs Accessibility: without it macOS drops the events silently, so ask rather than
    /// appear to do nothing.
    static func post(_ sequence: KeySequence) {
        guard AccessibilityTrust.shared.isTrusted else {
            AccessibilityTrust.shared.request()
            Toast.show("ToolHUD needs Accessibility access to press keys. Turn it on in System Settings › Privacy & Security.",
                       symbol: "hand.raised")
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for (i, press) in sequence.keys.enumerated() {
            var modifiers = sequence.modifiers
            if press.shift { modifiers.insert(.shift) }
            let flags = Shortcut(keyCode: press.keyCode, modifiers: modifiers, key: press.key).cgFlags
            // A short gap between keys, so apps that read a chord (⌘K, then ⌘S) see two presses.
            if i > 0 { usleep(15_000) }
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(press.keyCode), keyDown: keyDown) else { continue }
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
                // The HID level, so other apps' global shortcuts (our lens apps' included) see it.
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

/// A short note in the middle of the screen with the pointer, which clicks pass through.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String) {
        #if DEBUG
        DebugHooks.trace("toast: \(text)")
        #endif
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.preferredMaxLayoutWidth = 380
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = .white
        let stack = NSStackView(views: [icon, label])
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 18)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.cornerCurve = .continuous
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        let size = stack.fittingSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 120,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    Toast.panel?.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { Toast.panel?.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        AppAppearance.followSystem(panel)
        return panel
    }
}

/// Chooses an item from an app's menus through Accessibility, the way a click would.
@MainActor
enum MenuPress {
    enum Outcome: Equatable {
        case done
        case notFound(String)
        case disabled
    }

    static func press(_ path: [String], in pid: pid_t) -> Outcome {
        let app = AXUIElementCreateApplication(pid)
        guard var level = value(app, kAXMenuBarAttribute).map({ $0 as! AXUIElement }) else { return .notFound(path.first ?? "") }
        for (i, wanted) in path.enumerated() {
            guard let item = items(of: level).first(where: { title(of: $0).map { MenuPath.matches($0, wanted) } ?? false }) else {
                return .notFound(wanted)
            }
            if i == path.count - 1 {
                if (value(item, kAXEnabledAttribute) as? Bool) == false { return .disabled }
                AXUIElementPerformAction(item, kAXPressAction as CFString)
                return .done
            }
            level = item
        }
        return .notFound(path.last ?? "")
    }

    /// The app's menus as titled paths, for picking one in Settings: top-level menus with
    /// their items, submenus followed one level down.
    static func allPaths(in pid: pid_t) -> [[String]] {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = value(app, kAXMenuBarAttribute).map({ $0 as! AXUIElement }) else { return [] }
        var paths: [[String]] = []
        func walk(_ element: AXUIElement, _ prefix: [String], depth: Int) {
            for item in items(of: element) {
                guard let title = title(of: item), !title.isEmpty else { continue }
                let hasSubmenu = !(children(of: item).isEmpty)
                if hasSubmenu, depth < 3 {
                    walk(item, prefix + [title], depth: depth + 1)
                } else if !prefix.isEmpty {
                    paths.append(prefix + [title])
                }
            }
        }
        // The Apple menu is the system's, not the app's.
        for top in items(of: bar).dropFirst() {
            guard let title = title(of: top) else { continue }
            walk(top, [title], depth: 1)
        }
        return paths
    }

    /// The items under a menu bar item or menu item: the children of its one AXMenu.
    private static func items(of element: AXUIElement) -> [AXUIElement] {
        let kids = children(of: element)
        if kids.count == 1, (value(kids[0], kAXRoleAttribute) as? String) == kAXMenuRole { return children(of: kids[0]) }
        return kids
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func title(of element: AXUIElement) -> String? {
        (value(element, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespaces)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
}
