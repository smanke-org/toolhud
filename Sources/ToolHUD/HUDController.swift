import AppKit
import Observation
import SwiftUI
import ToolHUDKit

/// What the HUD views draw: the buttons, which one is lit, and the clock its animations
/// run on.
@Observable
@MainActor
final class HUDModel {
    var slots: [Slot] = []
    /// The button pad's buttons; they follow the ring's in `highlighted` and `fired`, so pad
    /// button 0 is `slots.count`.
    var padSlots: [Slot] = []
    /// Where the pad goes, or nil when it's off.
    var padPosition: PadPosition?
    var visualization: Visualization = .halo
    var opacity = 0.8
    var highlighted: Int?
    var fired: Int?
    /// The pointer is on the Settings gear.
    var gearHovered = false
    /// Each Glass Pill's width as drawn, for hit testing. Not observed: it changes nothing on
    /// screen.
    @ObservationIgnored var pillWidths: [Int: Double] = [:]
    /// Seconds since the HUD opened (the opening animations run on it), and when it fired.
    var time = 0.0
    var firedAt = 0.0
    /// Degrees the Planetary orbits have turned.
    var phase = 0.0
    /// Which button the Dial has turned to, counting whole turns, so it always takes the
    /// short way round.
    var dialIndex = 0
    /// The Size setting.
    var scale = 1.0
    /// What the readout says while no button is lit, when there's something to say, such
    /// as the center running the last action again.
    var hint: (title: String, app: String, detail: String)?
    /// / opens the search.
    var searchAvailable = false
    /// The open folder's name, while a folder's buttons are showing.
    var folderName: String?
    /// The search card is up, with what's been typed and what it found.
    var searching = false
    var query = ""
    var results: [SearchResult] = []
    var resultIndex = 0
    /// Buttons show whether their feature is on.
    var showsStateLights = false

    init() {}

    /// A still picture for Settings: fully open, with the first button lit.
    init(preview visualization: Visualization, slots: [Slot], opacity: Double) {
        self.visualization = visualization
        self.slots = slots
        self.opacity = opacity
        highlighted = 0
        time = 10
        phase = 20
    }

    var centers: [HUDPoint] { HUDLayout.centers(for: visualization, count: slots.count, phase: phase) }

    /// The look draws a Settings gear.
    var hasGear: Bool { HUDLayout.gearCenter(for: visualization, count: slots.count) != nil }

    /// The button the readout describes.
    var focus: Int? { fired ?? highlighted }

    /// The pad, if it's on.
    var pad: PadSpec? {
        guard let padPosition, !padSlots.isEmpty else { return nil }
        return PadSpec(look: visualization, ringCount: slots.count, position: padPosition, count: padSlots.count)
    }

    /// The key that runs a button: its number on the ring, its letter on the pad.
    func keyName(of index: Int) -> String {
        index < slots.count ? "\(index + 1)" : DefaultPad.keyLetters[min(index - slots.count, DefaultPad.keyLetters.count - 1)]
    }

    /// The ring's buttons and then the pad's.
    var buttonCount: Int { slots.count + (pad?.count ?? 0) }

    func slot(at index: Int) -> Slot? {
        if index < slots.count { return index >= 0 ? slots[index] : nil }
        guard pad != nil, index - slots.count < padSlots.count else { return nil }
        return padSlots[index - slots.count]
    }

    /// Turns the Dial to `index` by the shorter direction.
    func turnDial(to index: Int) {
        let n = max(slots.count, 1)
        let current = ((dialIndex % n) + n) % n
        var delta = ((index - current) % n + n) % n
        if delta > n / 2 { delta -= n }
        dialIndex += delta
    }
}

/// A borderless panel that takes the keyboard without making ToolHUD the active app, so
/// the app you were using stays in front and gets its keystrokes back when the HUD closes.
final class HUDPanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // Set outright: a clear window otherwise lets clicks through to the app underneath
        // wherever the window server sees no drawing, which can be the whole HUD.
        ignoresMouseEvents = false
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    // Swallowed rather than beeping.
    override func flagsChanged(with event: NSEvent) {}
}

/// Hosts the HUD's SwiftUI drawing and hands clicks and scrolling to the controller, which
/// decides from the pointer what was chosen (the drawing itself isn't interactive).
final class HUDHostingView: NSHostingView<HUDRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { HUDController.shared.click() }
    override func rightMouseDown(with event: NSEvent) { HUDController.shared.click() }
    override func scrollWheel(with event: NSEvent) { HUDController.shared.scroll(event.scrollingDeltaY) }
}

/// Opens, drives and closes the HUD.
@MainActor
final class HUDController {
    static let shared = HUDController()

    let model = HUDModel()
    private(set) var isShowing = false
    private(set) var lastUsed = Date.distantPast

    private var panel: HUDPanel?
    /// The HUD's center on screen, in Cocoa coordinates.
    private var center = CGPoint.zero
    private var scale = 1.0
    private var openPointer = CGPoint.zero
    /// The pointer has moved since the HUD opened: a release then runs what it points at.
    private var pointerMoved = false
    /// Where the pointer was when the keyboard or scroll wheel last chose a button; the
    /// pointer takes over again once it moves away from there.
    private var keyboardPointer: CGPoint?
    private var closing = false
    private var ticker: Timer?
    private var outsideMonitor: Any?
    /// Catches the HUD's keys while it's open; see `installKeyTap`.
    fileprivate var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var lastScroll = Date.distantPast
    /// The keys that run pad buttons, A S D F… where the current keyboard layout puts them.
    private var padKeyCodes = DefaultPad.usKeyCodes
    /// The rings under the open folder, to go back to.
    private var levels: [Level] = []
    /// Everything search can find, gathered when the search opens.
    private var searchIndex: [SearchResult] = []

    private struct Level {
        var slots: [Slot]
        var padSlots: [Slot]
        var padPosition: PadPosition?
        var folderName: String?
    }

    private static let tick = 1.0 / 60

    func start() {
        HotKeyCenter.shared.onPress = { HUDController.shared.hotKeyPressed() }
        HotKeyCenter.shared.onRelease = { HUDController.shared.hotKeyReleased() }
        MouseTriggers.shared.onOpen = { HUDController.shared.mouseOpened() }
        MouseTriggers.shared.onRelease = { HUDController.shared.triggerReleased() }
    }

    // MARK: - Triggers

    private func hotKeyPressed() {
        if isShowing { dismiss() } else { show() }
    }

    private func hotKeyReleased() { triggerReleased() }

    private func mouseOpened() {
        if isShowing { dismiss() } else { show() }
    }

    /// Letting go of the shortcut or mouse button leaves the HUD open: buttons run only when
    /// clicked or picked with the keyboard.
    private func triggerReleased() {}

    // MARK: - Showing

    func toggle() {
        if isShowing { dismiss() } else { show() }
    }

    /// Opens the HUD at the pointer (or the screen's center, per Settings), with the ring
    /// for the app in front, or the one `ring` names.
    func show(atScreenCenter forceCenter: Bool = false, ring: RingLookup.Match? = nil) {
        let prefs = Preferences.shared
        #if DEBUG
        DebugHooks.trace("show ring=\(String(describing: ring)) showing=\(isShowing)")
        #endif
        guard !prefs.visibleSlots.isEmpty else { return }
        let appRing: AppRing? = {
            switch ring {
            case .app(let id): return prefs.appRings.first { $0.bundleID == id }
            case .usual, .folder: return nil
            case nil: return prefs.appRing(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        }()
        model.slots = appRing?.visibleSlots ?? prefs.visibleSlots
        model.padSlots = appRing?.visiblePadSlots ?? prefs.visiblePadSlots
        model.padPosition = prefs.padEnabled ? prefs.padPosition : nil
        model.folderName = nil
        model.hint = nil
        model.searching = false
        model.query = ""
        model.results = []
        model.searchAvailable = prefs.searchEnabled
        model.showsStateLights = prefs.stateLightsEnabled
        levels = []
        if prefs.stateLightsEnabled { FeatureStates.shared.requestRefresh() }
        model.visualization = prefs.visualization
        #if DEBUG
        if let look = DebugHooks.look { model.visualization = look }
        if DebugHooks.sampleButtons { model.slots = Array(DefaultRing.slots.prefix(DefaultRing.defaultCount)) }
        if let pad = DebugHooks.pad {
            model.padPosition = pad.position
            model.padSlots = Array((DebugHooks.sampleButtons ? DefaultPad.slots : prefs.padSlots).prefix(pad.count))
        }
        #endif
        model.opacity = prefs.opacity
        model.highlighted = nil
        model.fired = nil
        model.gearHovered = false
        model.time = 0
        model.dialIndex = 0
        closing = false
        keyboardPointer = nil
        if model.pad != nil {
            padKeyCodes = zip(DefaultPad.keyLetters, DefaultPad.usKeyCodes).map { letter, fallback in
                KeyboardLayout.key(for: Character(letter.lowercased()))?.keyCode ?? fallback
            }
        }
        scale = prefs.size.scale
        model.scale = scale

        let mouse = NSEvent.mouseLocation
        var screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        #if DEBUG
        if let debugScreen = DebugHooks.screen { screen = debugScreen }
        #endif
        guard let screen else { return }
        let visible = screen.visibleFrame
        let wanted = prefs.anchor == .pointer && !forceCenter ? mouse : CGPoint(x: visible.midX, y: visible.midY)
        // Kept far enough from the edges that every button, the pad's too, is on screen.
        // The HUD's y runs down and the screen's up.
        let keep = HUDLayout.visibleBounds(pad: model.pad, ringRadius: HUDLayout.canvas * 0.43)
        let placed = HUDLayout.clamp(x: Double(wanted.x), y: Double(wanted.y),
                                     extent: .init(minX: keep.minX * scale, minY: -keep.maxY * scale,
                                                   maxX: keep.maxX * scale, maxY: -keep.minY * scale),
                                     bounds: (minX: Double(visible.minX), minY: Double(visible.minY),
                                              maxX: Double(visible.maxX), maxY: Double(visible.maxY)))
        center = CGPoint(x: placed.x, y: placed.y)
        openPointer = mouse
        pointerMoved = false

        let panel = self.panel ?? makePanel()
        self.panel = panel
        placePanel()
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)

        isShowing = true
        lastUsed = Date()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { _ in
            MainActor.assumeIsolated { HUDController.shared.step() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated { HUDController.shared.dismiss() }
        }
        installKeyTap()
        step()
        if case .folder(let folder) = ring { openFolder(folder) }
    }

    /// The panel covers the drawing, which grows to one side for the pad, plus room for the
    /// shadow.
    private func placePanel() {
        guard let panel else { return }
        let box = HUDLayout.drawingBounds(pad: model.pad), margin = HUDRootView.shadowMargin
        panel.setFrame(NSRect(x: center.x + box.minX * scale - margin, y: center.y - box.maxY * scale - margin,
                              width: box.width * scale + margin * 2, height: box.height * scale + margin * 2), display: true)
    }

    // MARK: - Folders

    /// Shows a folder's buttons in place of the ring's; Esc comes back.
    func openFolder(_ folder: Slot) {
        let buttons = folder.folderButtons
        guard isShowing, !buttons.isEmpty else {
            if !isShowing { show(ring: .folder(folder)) }
            return
        }
        levels.append(Level(slots: model.slots, padSlots: model.padSlots, padPosition: model.padPosition,
                            folderName: model.folderName))
        enter(slots: buttons, padSlots: [], padPosition: nil, folderName: folder.name)
    }

    /// Back out of the open folder. False when there's none.
    private func closeFolder() -> Bool {
        guard let level = levels.popLast() else { return false }
        enter(slots: level.slots, padSlots: level.padSlots, padPosition: level.padPosition, folderName: level.folderName)
        return true
    }

    private func enter(slots: [Slot], padSlots: [Slot], padPosition: PadPosition?, folderName: String?) {
        model.slots = slots
        model.padSlots = padSlots
        model.padPosition = padPosition
        model.folderName = folderName
        model.highlighted = nil
        model.fired = nil
        model.hint = nil
        model.dialIndex = 0
        model.time = 0
        model.pillWidths = [:]
        closing = false
        keyboardPointer = nil
        placePanel()
    }

    func dismiss() {
        guard isShowing else { return }
        isShowing = false
        closing = false
        ticker?.invalidate()
        ticker = nil
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        removeKeyTap()
        panel?.orderOut(nil)
        // Hidden in the middle of its own click, the panel can stay on screen though AppKit
        // reports it hidden (macOS 27); the window server seems to hold it until the mouse
        // button comes up. Hide it again once the click is surely over.
        for delay in [0.05, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    if !HUDController.shared.isShowing { HUDController.shared.panel?.orderOut(nil) }
                }
            }
        }
        model.highlighted = nil
        model.fired = nil
        model.gearHovered = false
        model.searching = false
        model.hint = nil
        levels = []
    }

    /// The keys the HUD answers to. Others pass through to the app in front.
    nonisolated static let hudKeys: Set<UInt16> = Set(KeyCode.digits).union([
        KeyCode.escape, KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.space, KeyCode.tab, KeyCode.comma,
        KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down,
    ])

    /// While the HUD is open over another app, AppKit calls the panel the key window but
    /// the window server keeps sending keys to the app in front, which never sees them
    /// either (macOS 27), so Esc and the number keys did nothing. An event tap takes the
    /// HUD's own keys first, whichever window has focus. It needs Accessibility; without
    /// it the panel's own keyDown is the fallback.
    private func installKeyTap() {
        guard keyTap == nil, AccessibilityTrust.shared.isTrusted else { return }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: hudKeyTapCallback, userInfo: nil) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        keyTapSource = source
    }

    private func removeKeyTap() {
        if let keyTap {
            CGEvent.tapEnable(tap: keyTap, enable: false)
            CFMachPortInvalidate(keyTap)
        }
        if let keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
        keyTap = nil
        keyTapSource = nil
    }

    /// From the key tap: whether the HUD used the key.
    fileprivate func tappedKey(_ event: NSEvent) -> Bool {
        guard isShowing, !closing else { return false }
        if model.searching {
            // Typing goes to the search, Option for accented letters included; ⌘ and ⌃
            // keys still belong to someone else.
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
            key(event)
            return true
        }
        let wanted = Self.hudKeys.contains(event.keyCode) || padIndex(forKey: event.keyCode) != nil
            || isSearchKey(event) || (event.keyCode == KeyCode.delete && !levels.isEmpty)
        guard wanted else { return false }
        // Keys with ⌘ ⌥ ⌃ belong to someone else (the HUD's own shortcut among them);
        // Shift is allowed for Shift-Tab.
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        key(event)
        return true
    }

    private func makePanel() -> HUDPanel {
        let panel = HUDPanel()
        let host = HUDHostingView(rootView: HUDRootView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.onKey = { event in HUDController.shared.key(event) }
        AppAppearance.followSystem(panel)
        return panel
    }

    // MARK: - Every frame

    private func step() {
        guard isShowing else { return }
        model.time += Self.tick
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - openPointer.x, mouse.y - openPointer.y) > 8 { pointerMoved = true }
        let local = HUDPoint(Double(mouse.x - center.x) / scale, -Double(mouse.y - center.y) / scale)

        // The planets drift until the pointer moves in among them.
        if model.visualization == .planetary, !pointerMoved || local.length > HUDLayout.planetOrbits.outer + 40 {
            model.phase += Self.tick * 9
        }
        guard model.fired == nil else { return }
        #if DEBUG
        if DebugHooks.freezeHighlight { return }
        #endif
        if let at = keyboardPointer {
            guard hypot(mouse.x - at.x, mouse.y - at.y) > 4 else { return }
            keyboardPointer = nil
        }
        if model.searching {
            if let row = SearchCardLayout.row(at: local, rows: model.results.count), row != model.resultIndex {
                model.resultIndex = row
            }
            return
        }
        let onGear = HUDLayout.pointsAtGear(local, in: model.visualization, count: model.slots.count)
        if onGear != model.gearHovered { model.gearHovered = onGear }
        let hit = onGear ? nil : button(at: local)
        setHighlight(hit)
        let again = hit == nil && !onGear && pointsAtRepeat(local) ? LastAction.slot : nil
        let hint = again.map { ("Run again", $0.name, "Click the center or press Space") }
        if hint?.1 != model.hint?.app || (hint == nil) != (model.hint == nil) { model.hint = hint }
    }

    /// The center runs the last action again, when that's turned on and there is one.
    private func pointsAtRepeat(_ local: HUDPoint) -> Bool {
        Preferences.shared.repeatLastEnabled && LastAction.slot != nil
            && RepeatTarget.contains(local, in: model.visualization)
    }

    /// Runs the last action again, from the center, Space or `toolhud://repeat`.
    func repeatLast() {
        guard let slot = LastAction.slot else {
            Toast.show("Nothing has run yet to run again.", symbol: "arrow.clockwise")
            return
        }
        if isShowing {
            closing = true
            model.hint = ("Running again", slot.name, "…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                MainActor.assumeIsolated {
                    HUDController.shared.dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        MainActor.assumeIsolated { HUDController.shared.runChosen(slot) }
                    }
                }
            }
        } else {
            runChosen(slot)
        }
    }

    #if DEBUG
    var debugPanel: NSPanel? { panel }
    var debugLevels: Int { levels.count }

    /// Shows `visualization` with button `highlight` lit, ignoring the pointer, for screenshots.
    /// A negative `highlight` leaves the pointer in charge; -2 shows the gear lit.
    func debugShow(_ visualization: Visualization, highlight: Int) {
        DebugHooks.freezeHighlight = highlight != -1
        DebugHooks.look = visualization
        show(atScreenCenter: true)
        if highlight >= 0 { model.highlighted = highlight }
        if highlight == -2 { model.gearHovered = true }
        if visualization == .dial, highlight >= 0 { model.turnDial(to: highlight) }
        if let gear = HUDLayout.gearCenter(for: visualization, count: model.slots.count), let screen = NSScreen.screens.first {
            // In CG coordinates (top-left origin), for a test click.
            let x = center.x + gear.x * scale, y = screen.frame.maxY - (center.y - gear.y * scale)
            DebugHooks.trace("gear at \(Int(x)) \(Int(y))")
            // Button 2's drawn center and an empty spot above everything, for test clicks.
            let n = model.slots.count
            let targets: [HUDPoint] = {
                switch visualization {
                case .commandDeck: return HUDLayout.deck(n).map { HUDPoint($0.x, $0.y + 3) }
                case .glassPills:
                    return HUDLayout.centers(for: .glassPills, count: n).enumerated().map {
                        HUDLayout.pillFrame($0.offset, count: n, anchor: $0.element, width: model.pillWidths[$0.offset] ?? 150).center
                    }
                default: return HUDLayout.centers(for: visualization, count: n, phase: model.phase)
                }
            }()
            var points = [("button", targets[min(1, n - 1)]), ("empty", HUDPoint(0, -285))]
            if let pad = model.pad {
                points.append(("pad button", HUDLayout.padItems(pad)[min(1, pad.count - 1)].center))
            }
            for (label, p) in points {
                DebugHooks.trace("\(label) at \(Int(center.x + p.x * scale)) \(Int(screen.frame.maxY - (center.y - p.y * scale)))")
            }
        }
    }
    #endif

    private func setHighlight(_ index: Int?) {
        guard index != model.highlighted else { return }
        model.highlighted = index
        guard index != nil else { return }
        if Preferences.shared.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: - Choosing

    /// The button drawn under this point, if any.
    private func button(at local: HUDPoint) -> Int? {
        if let pad = model.pad, let index = HUDLayout.padButton(at: local, in: pad) {
            return model.slots.count + index
        }
        let n = max(model.slots.count, 1)
        return HUDLayout.button(at: local, in: model.visualization, count: model.slots.count,
                                dialTurn: Double(model.dialIndex) * 360 / Double(n), phase: model.phase,
                                pillWidths: model.pillWidths)
    }

    /// Where the pointer is, in the HUD's own coordinates.
    private var pointerInHUD: HUDPoint {
        let mouse = NSEvent.mouseLocation
        return HUDPoint(Double(mouse.x - center.x) / scale, -Double(mouse.y - center.y) / scale)
    }

    /// A click runs the button it lands on, opens Settings on the gear, and closes the HUD
    /// anywhere else, even if the keyboard has lit a button.
    func click(at point: HUDPoint? = nil) {
        guard isShowing, !closing else { return }
        let local = point ?? pointerInHUD
        if model.searching {
            if let row = SearchCardLayout.row(at: local, rows: model.results.count) {
                model.resultIndex = row
                runResult()
            } else if !SearchCardLayout.contains(local, rows: model.results.count) {
                endSearch()
            }
            return
        }
        if HUDLayout.pointsAtGear(local, in: model.visualization, count: model.slots.count) {
            openSettings()
        } else if let index = button(at: local) {
            fire(index)
        } else if pointsAtRepeat(local) {
            repeatLast()
        } else {
            dismiss()
        }
    }

    /// Closes the HUD and opens Settings, from the gear or the comma key.
    private func openSettings() {
        dismiss()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                SettingsWindow.shared.show()
                // Activating the app as Settings opens puts the just-hidden panel back on
                // screen (macOS 27), though AppKit still reports it hidden; hide it again.
                HUDController.shared.panel?.orderOut(nil)
            }
        }
    }

    func scroll(_ delta: CGFloat) {
        guard isShowing, !closing, abs(delta) > 2, Date().timeIntervalSince(lastScroll) > 0.12 else { return }
        lastScroll = Date()
        move(delta > 0 ? 1 : -1)
    }

    private func move(_ by: Int) {
        let n = model.buttonCount
        guard n > 0 else { return }
        let current = model.highlighted ?? (by > 0 ? -1 : 0)
        keyboardPointer = NSEvent.mouseLocation
        model.gearHovered = false
        let next = ((current + by) % n + n) % n
        setHighlight(next)
        if model.visualization == .dial, next < model.slots.count { model.turnDial(to: next) }
    }


    /// The pad button this key runs, if the pad is showing and has that many buttons.
    private func padIndex(forKey code: UInt16) -> Int? {
        guard let pad = model.pad, let index = padKeyCodes.firstIndex(of: code), index < pad.count else { return nil }
        return index
    }

    /// The / key, wherever the keyboard layout puts it.
    private func isSearchKey(_ event: NSEvent) -> Bool {
        Preferences.shared.searchEnabled && event.charactersIgnoringModifiers == "/"
    }

    func key(_ event: NSEvent) {
        guard isShowing, !closing else { return }
        let code = event.keyCode
        if model.searching {
            searchKey(event)
            return
        }
        if isSearchKey(event) {
            startSearch()
            return
        }
        if let digit = KeyCode.digits.firstIndex(of: code) {
            if digit < model.slots.count { fire(digit) } else { NSSound.beep() }
            return
        }
        if let index = padIndex(forKey: code) {
            fire(model.slots.count + index)
            return
        }
        switch code {
        case KeyCode.escape:
            if !closeFolder() { dismiss() }
        case KeyCode.delete:
            _ = closeFolder()
        case KeyCode.comma:
            openSettings()
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.space:
            if let index = model.highlighted {
                fire(index)
            } else if code == KeyCode.space, Preferences.shared.repeatLastEnabled {
                repeatLast()
            }
        case KeyCode.right, KeyCode.down:
            move(1)
        case KeyCode.left, KeyCode.up:
            move(-1)
        case KeyCode.tab:
            move(event.modifierFlags.contains(.shift) ? -1 : 1)
        default:
            break
        }
    }

    /// Shows the button as chosen for a moment, closes the HUD, then runs it once the app
    /// underneath has the keyboard back.
    private func fire(_ index: Int) {
        guard let slot = model.slot(at: index), !closing else { return }
        if slot.mode == .folder {
            if Preferences.shared.foldersEnabled {
                if Preferences.shared.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
                openFolder(slot)
                ActivityStore.shared.record()
            } else {
                Toast.show("Folders are turned off. Turn them on in ToolHUD Settings › Features.", symbol: "folder")
            }
            return
        }
        closing = true
        model.highlighted = index
        model.fired = index
        model.firedAt = model.time
        lastUsed = Date()
        ActivityStore.shared.record()
        if Preferences.shared.playSound { NSSound(named: "Pop")?.play() }
        let hold = model.visualization.fireDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            MainActor.assumeIsolated {
                HUDController.shared.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    MainActor.assumeIsolated { HUDController.shared.runChosen(slot) }
                }
            }
        }
    }

    /// Runs what the user chose in the HUD, and remembers it for running again.
    func runChosen(_ slot: Slot) {
        LastAction.record(slot)
        ActionRunner.run(slot)
    }

    // MARK: - Search

    func startSearch() {
        guard isShowing, !closing, Preferences.shared.searchEnabled else { return }
        searchIndex = SearchSource.gather(currentRing: model.slots + model.padSlots)
        model.searching = true
        model.query = ""
        model.highlighted = nil
        model.gearHovered = false
        model.hint = nil
        updateResults()
        // The Shortcuts app's list comes from a slower command, so it joins when ready.
        SearchSource.loadShortcuts { names in
            guard HUDController.shared.model.searching else { return }
            HUDController.shared.searchIndex += SearchSource.shortcutResults(names)
            HUDController.shared.updateResults()
        }
    }

    private func endSearch() {
        model.searching = false
        model.query = ""
        model.results = []
    }

    private func updateResults() {
        model.results = SearchSource.rank(searchIndex, query: model.query)
        model.resultIndex = min(model.resultIndex, max(model.results.count - 1, 0))
        if model.query.isEmpty { model.resultIndex = 0 }
    }

    private func searchKey(_ event: NSEvent) {
        switch event.keyCode {
        case KeyCode.escape:
            endSearch()
        case KeyCode.returnKey, KeyCode.keypadEnter:
            runResult()
        case KeyCode.delete:
            if model.query.isEmpty { endSearch() } else { model.query.removeLast(); updateResults() }
        case KeyCode.down, KeyCode.tab where !event.modifierFlags.contains(.shift):
            if !model.results.isEmpty { model.resultIndex = (model.resultIndex + 1) % model.results.count }
            keyboardPointer = NSEvent.mouseLocation
        case KeyCode.up, KeyCode.tab:
            if !model.results.isEmpty { model.resultIndex = (model.resultIndex - 1 + model.results.count) % model.results.count }
            keyboardPointer = NSEvent.mouseLocation
        case KeyCode.left, KeyCode.right, KeyCode.forwardDelete:
            break
        default:
            guard let typed = event.characters, !typed.isEmpty,
                  typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            model.query += typed
            model.resultIndex = 0
            updateResults()
        }
    }

    private func runResult() {
        #if DEBUG
        DebugHooks.trace("runResult index=\(model.resultIndex) of \(model.results.count) closing=\(closing)")
        #endif
        guard model.results.indices.contains(model.resultIndex) else {
            NSSound.beep()
            return
        }
        let result = model.results[model.resultIndex]
        ActivityStore.shared.record()
        if case .button(let slot) = result.target, slot.mode == .folder, Preferences.shared.foldersEnabled {
            endSearch()
            openFolder(slot)
            return
        }
        closing = true
        if Preferences.shared.playSound { NSSound(named: "Pop")?.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            MainActor.assumeIsolated {
                HUDController.shared.dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    MainActor.assumeIsolated {
                        switch result.target {
                        case .button(let slot): HUDController.shared.runChosen(slot)
                        case .menuItem(let bundleID, let path): MenuHubHost.shared.invoke(bundleID: bundleID, path: path)
                        }
                    }
                }
            }
        }
    }
}

private func hudKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { if let tap = HUDController.shared.keyTap { CGEvent.tapEnable(tap: tap, enable: true) } }
        return Unmanaged.passUnretained(event)
    }
    // Keystrokes ToolHUD itself posts (a button's keys) go on to the app.
    guard type == .keyDown, event.getIntegerValueField(.eventSourceUserData) != ActionRunner.eventMarker,
          let key = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
    // The tap's run loop source is on the main run loop, so this is the main thread.
    nonisolated(unsafe) let mainKey = key
    let used = MainActor.assumeIsolated { HUDController.shared.tappedKey(mainKey) }
    return used ? nil : Unmanaged.passUnretained(event)
}
