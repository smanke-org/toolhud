#if DEBUG
import AppKit
import SwiftUI
import ToolHUDKit

/// The demo video, played on the built-in display for `TOOLHUD_DEBUG_SCENARIO=demo`
/// (with TOOLHUD_DEBUG_DRY_RUN=1, so nothing chosen runs). Everything on screen is one of
/// ToolHUD's own windows: a wallpaper, the HUD and Settings, then a pointer, captions and
/// title cards on top. A recorder that captures only ToolHUD's windows films it, so
/// nothing else on the screen gets in. The real pointer and keyboard are left alone.
///
/// The film is cropped to `crop`: 16:9, below the menu bar and the notch.
@MainActor
enum DemoStage {
    static let selectButton = Notification.Name("ToolHUDDemoSelectButton")
    static let state = DemoOverlayState()
    private static var screen: NSScreen!
    /// The filmed area, in screen coordinates.
    static var crop = CGRect.zero
    private static var windows: [NSWindow] = []

    // Window levels: the wallpaper under Settings, Settings under the HUD, and the
    // pointer and captions over everything.
    private static let wallpaperLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 2)
    private static let settingsLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
    private static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)

    static func run() {
        guard let built = NSScreen.screens.first(where: {
            CGDisplayIsBuiltin(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) != 0
        }) else { DebugHooks.trace("no built-in display"); return }
        screen = built
        let frame = built.frame
        let width = frame.width, height = (width * 9 / 16).rounded()
        let top = frame.maxY - 88
        crop = CGRect(x: frame.minX, y: top - height, width: width, height: height)
        DebugHooks.trace("crop \(crop) screen \(frame) scale \(built.backingScaleFactor)")
        // The recorder wants this in the display's own top-left coordinates.
        let topLeft = CGRect(x: 0, y: frame.maxY - crop.maxY, width: crop.width, height: crop.height)
        try? "\(Int(topLeft.minX)) \(Int(topLeft.minY)) \(Int(topLeft.width)) \(Int(topLeft.height))"
            .write(toFile: (ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_TRACE"] ?? "/dev/null") + ".crop",
                   atomically: true, encoding: .utf8)

        stagePrefs()
        LensDirectory.shared.refresh()
        makeWindows()
        DebugPointer.set(CGPoint(x: crop.midX, y: crop.midY))
        // The recorder starts once it sees this line.
        DebugHooks.trace("stage ready")
        pump(Double(ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_DEMO_LEAD"] ?? "") ?? 3)
        DebugHooks.trace("action")
        play()
        DebugHooks.trace("cut")
        pump(0.5)
        for window in windows { window.orderOut(nil) }
    }

    // MARK: - The buttons

    private static func lens(_ id: String, _ feature: String, _ name: String) -> Slot {
        guard let app = LensDirectory.shared.app(id) else {
            DebugHooks.trace("missing app \(id)")
            return Slot(name: name, symbol: "questionmark.circle", mode: .keystroke)
        }
        var slot = Slot(app, feature)
        slot.name = name
        return slot
    }

    private static var ring: [Slot] {
        [
            lens("com.smanke.CaptureLens", "capture", "Capture"),
            lens("com.smanke.TextLens", "capture", "Capture text"),
            lens("com.smanke.PasteLens", "open", "Clipboard"),
            lens("com.smanke.ClickLens", "spotlight", "Spotlight"),
            lens("com.smanke.ExpansionLens", "open", "Snippets"),
            lens("com.smanke.GridLock", "grid", "Window grid"),
            lens("com.smanke.AudioLens", "compact", "Volume"),
            lens("com.smanke.DiskLens", "open", "Disk space"),
        ]
    }

    private static var pad: [Slot] {
        [
            lens("com.smanke.WindowKeeper", "restore", "Restore windows"),
            lens("com.smanke.NetworkToggle", "use-wired", "Go wired"),
            lens("com.smanke.StayMounted", "mount-all", "Mount shares"),
            lens("com.smanke.BatteryLens", "menu", "Batteries"),
            lens("com.smanke.MouseMileage", "today", "Mouse miles"),
            lens("com.smanke.ShortcutsLens", "quickview", "Shortcuts"),
            lens("com.smanke.DockMirror", "sync", "Sync Dock"),
            lens("com.smanke.DynamicNotch", "show", "Notch"),
        ]
    }

    private static var desktopFolder: Slot {
        Slot(name: "Desktop", symbol: "folder", mode: .folder, children: [
            lens("com.smanke.DesktopBinsWidget", "new-bin", "New bin"),
            lens("com.smanke.DesktopBinsWidget", "toggle", "Hide bins"),
            lens("com.smanke.WindowKeeper", "save", "Save windows"),
            lens("com.smanke.GridLock", "snap-left-half", "Left half"),
            lens("com.smanke.GridLock", "snap-right-half", "Right half"),
            lens("com.smanke.DynamicNotch", "clear", "Clear notch"),
        ])
    }

    /// In memory only: staging runs never save.
    private static func stagePrefs() {
        let prefs = Preferences.shared
        prefs.anchor = .pointer
        prefs.size = .large
        prefs.playSound = false
        prefs.haptics = false
        prefs.searchEnabled = true
        prefs.repeatLastEnabled = true
        prefs.foldersEnabled = true
        prefs.appRingsEnabled = false
        prefs.stateLightsEnabled = false
        prefs.appMenuButtonsEnabled = true
        prefs.doubleTapKey = .option
        prefs.hotCorner = .bottomLeft
        prefs.visualization = .liquidGlass
        prefs.slots = ring + Array(DefaultRing.slots.dropFirst(ring.count))
        prefs.slotCount = ring.count
        prefs.padSlots = pad
        prefs.padCount = pad.count
        prefs.padEnabled = true
        prefs.padPosition = .right
        let c = LensCatalog.self
        prefs.appRings = [AppRing(bundleID: "com.apple.Safari", name: "Safari", slots: [
            lens("com.smanke.CaptureLens", "scrolling", "Whole page"),
            Slot(name: "Reader", symbol: "doc.plaintext", mode: .keystroke,
                 keys: KeySequence(Shortcut(keyCode: 15, modifiers: [.command, .shift], key: "R"))),
            Slot(c.textLens, "translate"),
            Slot(name: "Export PDF", symbol: "filemenu.and.selection", mode: .menuItem, menuPath: ["File", "Export as PDF…"]),
            Slot(name: "Sign-off", symbol: "character.cursor.ibeam", mode: .text, text: "Thanks,\nAlex", textMethod: .paste),
            Slot(name: "New tab", symbol: "plus.square.on.square", mode: .keystroke,
                 keys: KeySequence(Shortcut(keyCode: 17, modifiers: [.command], key: "T"))),
        ], slotCount: 6, padSlots: [], padCount: 0)]
    }

    // MARK: - The windows

    private static func window(level: NSWindow.Level, frame: CGRect, view: some View) -> NSWindow {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: view)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        windows.append(window)
        return window
    }

    private static func makeWindows() {
        let frame = screen.frame
        _ = window(level: wallpaperLevel, frame: frame, view: DemoWallpaper())
        let cropInView = CGRect(x: crop.minX - frame.minX, y: frame.maxY - crop.maxY, width: crop.width, height: crop.height)
        _ = window(level: overlayLevel, frame: frame, view: DemoOverlayView(state: state, crop: cropInView))
    }

    /// Screen point → the overlay's own top-left coordinates.
    static func viewPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - screen.frame.minX, y: screen.frame.maxY - p.y)
    }

    // MARK: - Moving and pressing

    static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Glides the pointer along a gentle curve, easing in and out.
    private static func glide(to target: CGPoint, _ duration: Double = 0.7, bend: Double = 0.12) {
        guard let start = DebugHooks.pointer else { DebugPointer.set(target); return }
        let dx = target.x - start.x, dy = target.y - start.y
        let begin = Date()
        while true {
            let t = min(1, Date().timeIntervalSince(begin) / duration)
            let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            let arc = sin(.pi * e) * bend
            DebugPointer.set(CGPoint(x: start.x + dx * e - dy * arc, y: start.y + dy * e + dx * arc))
            if t >= 1 { break }
            RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))
        }
    }

    private static func glide(toButton index: Int, _ duration: Double = 0.55) {
        glide(to: buttonPoint(index), duration)
    }

    /// A button's drawn center on screen; pad buttons follow the ring's.
    private static func buttonPoint(_ index: Int) -> CGPoint {
        let model = HUDController.shared.model
        let n = model.slots.count
        if index >= n, let pad = model.pad {
            return HUDController.shared.debugScreenPoint(HUDLayout.padItems(pad)[index - n].center)
        }
        let centers = HUDLayout.centers(for: model.visualization, count: n, phase: model.phase)
        return HUDController.shared.debugScreenPoint(centers[index])
    }

    private static func click() {
        state.clicks += 1
        pump(0.08)
        HUDController.shared.click()
    }

    private static func key(_ code: UInt16, _ characters: String = "", shown: String? = nil) {
        if let shown { state.keys = [shown] }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: code) else { return }
        HUDController.shared.key(event)
        pump(0.05)
    }

    private static func type(_ text: String, every: Double = 0.16) {
        for ch in text {
            key(0, String(ch))
            pump(every)
        }
    }

    private static func caption(_ title: String?, _ detail: String? = nil, keys: [String] = []) {
        state.caption = title
        state.detail = detail
        state.keys = keys
    }

    /// Opens the HUD at the pointer, as the shortcut does.
    private static func openHUD(ring: RingLookup.Match? = nil) {
        state.keys = ["⌃", "⌥", "⌘", "Space"]
        HUDController.shared.show(ring: ring)
        pump(0.15)
    }

    private static func dismissHUD() {
        HUDController.shared.dismiss()
        pump(0.35)
    }

    // MARK: - The film

    private static func play() {
        let mid = CGPoint(x: crop.midX, y: crop.midY + 36)
        let prefs = Preferences.shared

        // 1. Title.
        state.showPointer = false
        state.card = DemoCard(title: "ToolHUD", subtitle: "Every tool you use, in a ring at your pointer.", footnote: "for macOS")
        pump(3.2)
        state.card = nil
        pump(0.6)

        // 2. Open the ring and click a button.
        DebugPointer.set(CGPoint(x: mid.x - 260, y: mid.y - 120))
        state.showPointer = true
        pump(0.3)
        glide(to: mid, 0.9)
        caption("Press a shortcut, or a mouse button", "The ring opens right where the pointer is", keys: ["⌃", "⌥", "⌘", "Space"])
        pump(1.0)
        openHUD()
        pump(1.2)
        caption("Each button runs a feature in another app", "SnagAnything, TextLens, PasteLens, ClickLens, ExpansionLens, GridLock…")
        for i in [0, 1, 2, 3, 4, 5, 6, 7] {
            glide(toButton: i, 0.4)
            pump(0.3)
        }
        caption("The pad holds eight more", "WindowKeeper, NetworkToggle, StayMounted, BatteryLens, M3 Tracker…")
        for i in 8..<16 {
            glide(toButton: i, 0.28)
            pump(0.18)
        }
        glide(toButton: 1, 0.7)
        caption("Click one to run it", "Capture text with TextLens")
        pump(0.5)
        click()
        pump(1.4)

        // 3. Keys.
        glide(to: mid, 0.5)
        caption("Or press its number", "Keys 1 to 0 for the ring", keys: ["⌃", "⌥", "⌘", "Space"])
        openHUD()
        pump(1.1)
        key(KeyCode.digits[2], "3", shown: "3")
        pump(1.2)
        caption("…or its letter for the pad", "A S D F G H J K", keys: ["⌃", "⌥", "⌘", "Space"])
        openHUD()
        pump(1.0)
        key(1, "s", shown: "S")
        pump(1.3)

        // 4. Looks.
        caption("Pick a look", nil)
        let looks: [Visualization] = [.halo, .orbit, .dial, .stargate, .commandDeck, .hive, .redAlert,
                                      .constellation, .glassPills, .planetary, .liquidGlass]
        state.showPointer = false
        DebugHooks.freezeHighlight = true
        for (n, look) in looks.enumerated() {
            prefs.visualization = look
            caption("Pick a look", "\(look.title) · \(n + 1) of \(looks.count)")
            HUDController.shared.show()
            let lit = [0, 2, 1, 3, 5, 4, 6, 2, 1, 3, 0][n]
            HUDController.shared.model.highlighted = lit
            if look == .dial { HUDController.shared.model.turnDial(to: lit) }
            pump(look == .liquidGlass ? 1.4 : 1.05)
            HUDController.shared.dismiss()
            pump(0.08)
        }
        DebugHooks.freezeHighlight = false
        pump(0.3)
        state.showPointer = true

        // 5. Search.
        caption("Type / to search", "Every button and feature, across all your apps", keys: ["⌃", "⌥", "⌘", "Space"])
        openHUD()
        pump(0.9)
        key(44, "/", shown: "/")
        pump(0.6)
        state.keys = []
        type("capture", every: 0.11)
        pump(1.2)
        key(KeyCode.down, shown: "↓")
        pump(0.5)
        key(KeyCode.down, shown: "↓")
        pump(0.6)
        key(KeyCode.returnKey, shown: "Return")
        pump(1.2)

        // 6. Folders.
        prefs.slots = Array(ring.prefix(7)) + [desktopFolder]
        prefs.slotCount = 8
        caption("Folders keep more close at hand", "Desktop Bins Widget, WindowKeeper, GridLock, DynamicNotch", keys: ["⌃", "⌥", "⌘", "Space"])
        openHUD()
        pump(0.9)
        glide(toButton: 7, 0.6)
        pump(0.4)
        click()
        pump(1.6)
        for i in [0, 1, 2, 3] {
            glide(toButton: i, 0.4)
            pump(0.35)
        }
        key(KeyCode.escape, shown: "Esc")
        pump(1.0)
        dismissHUD()
        prefs.slots = ring + Array(DefaultRing.slots.dropFirst(ring.count))
        prefs.slotCount = ring.count

        // 7. A ring for each app.
        prefs.appRingsEnabled = true
        prefs.padEnabled = false
        glide(to: mid, 0.4)
        caption("A ring of its own for each app", "Here, the buttons for Safari", keys: ["⌃", "⌥", "⌘", "Space"])
        openHUD(ring: .app("com.apple.Safari"))
        pump(0.8)
        for i in [0, 1, 2, 3, 4, 5] {
            glide(toButton: i, 0.4)
            pump(0.3)
        }
        dismissHUD()
        prefs.padEnabled = true

        // 8. Lights and running again.
        prefs.stateLightsEnabled = true
        glide(to: mid, 0.4)
        caption("Lights show what’s on", "ClickLens Spotlight and ExpansionLens are on", keys: ["⌃", "⌥", "⌘", "Space"])
        openHUD()
        for _ in 0..<12 {
            FeatureStates.shared.debugSet("com.smanke.ClickLens", ["spotlight": true])
            FeatureStates.shared.debugSet("com.smanke.ExpansionLens", ["open": true])
            pump(0.1)
        }
        pump(0.8)
        glide(to: HUDController.shared.debugScreenPoint(HUDPoint(0, 0)), 0.6)
        caption("Click the center to run the last one again", "Or press Space")
        pump(1.6)
        click()
        pump(1.3)
        prefs.stateLightsEnabled = false

        // 9. Settings.
        state.showPointer = false
        caption("Make it yours in Settings", nil)
        DemoStage.stageKinds()
        settings(.buttons)
        caption("Build your own buttons", "App features, shortcuts, text, menu items, scripts, steps and folders")
        pump(0.5)
        for i in [0, 1, 2, 3, 4, 5] {
            NotificationCenter.default.post(name: selectButton, object: i)
            pump(1.1)
        }
        caption("Choose a look and see it live", nil)
        prefs.slots = ring + Array(DefaultRing.slots.dropFirst(ring.count))
        prefs.slotCount = ring.count
        settings(.appearance)
        for look in [Visualization.halo, .hive, .stargate, .liquidGlass] {
            prefs.visualization = look
            pump(1.0)
        }
        caption("Open it your way", "Shortcut, mouse button, double-tap a modifier, or a screen corner")
        settings(.triggers)
        pump(2.6)
        caption("Turn on just the features you want", nil)
        settings(.features)
        pump(2.4)
        SettingsWindow.shared.debugWindow?.orderOut(nil)
        caption(nil)
        pump(0.4)

        // 10. End.
        state.card = DemoCard(title: "ToolHUD", subtitle: "Works with all of my Mac apps.", footnote: "stevemanke.com/toolhud")
        pump(3.6)
    }

    /// Buttons of each kind for the editor in Settings.
    private static func stageKinds() {
        let prefs = Preferences.shared
        prefs.slots = [
            lens("com.smanke.CaptureLens", "capture", "Capture"),
            Slot(name: "Paste plain", symbol: "keyboard", mode: .keystroke,
                 keys: KeySequence(Shortcut(keyCode: 9, modifiers: [.command, .option, .shift], key: "V"))),
            Slot(name: "Sign-off", symbol: "character.cursor.ibeam", mode: .text, text: "Thanks,\nAlex", textMethod: .paste),
            Slot(name: "Export PDF", symbol: "filemenu.and.selection", mode: .menuItem, menuPath: ["File", "Export as PDF…"]),
            Slot(name: "Morning", symbol: "list.number", mode: .chain, steps: [
                ChainStep(action: lens("com.smanke.WindowKeeper", "restore", "Restore windows"), delay: 0.5),
                ChainStep(action: lens("com.smanke.StayMounted", "mount-all", "Mount shares"), delay: 1),
                ChainStep(action: lens("com.smanke.AudioLens", "compact", "Volume"), delay: 0),
            ]),
            desktopFolder,
            lens("com.smanke.ClickLens", "spotlight", "Spotlight"),
            lens("com.smanke.DiskLens", "open", "Disk space"),
        ]
        prefs.slotCount = 8
    }

    /// Shows a Settings pane over the wallpaper, in the middle of the film.
    private static func settings(_ pane: SettingsPane) {
        let first = SettingsWindow.shared.debugWindow?.isVisible != true
        if first { SettingsWindow.shared.show(.appearance) }
        SettingsWindow.shared.show(pane)
        guard let window = SettingsWindow.shared.debugWindow else { return }
        window.level = settingsLevel
        if first {
            window.setFrameAutosaveName("")
            window.isRestorable = false
            let size = NSSize(width: 1080, height: 800)
            let target = NSRect(x: crop.midX - size.width / 2, y: crop.midY - size.height / 2 + 30,
                                width: size.width, height: size.height)
            pump(0.3)
            // The window server ignores moves of a window already on screen.
            window.orderOut(nil)
            window.setFrame(target, display: true)
            window.orderFrontRegardless()
            window.makeKey()
            pump(1.0)
        } else {
            pump(0.5)
        }
    }
}

/// Moves the demo's own pointer, which the HUD follows in place of the real one.
@MainActor
enum DebugPointer {
    static func set(_ p: CGPoint) {
        DebugHooks.pointer = p
        DemoStage.state.pointer = DemoStage.viewPoint(p)
    }
}

struct DemoCard: Equatable {
    var title: String
    var subtitle: String
    var footnote: String
}

@Observable
@MainActor
final class DemoOverlayState {
    var pointer = CGPoint.zero
    var showPointer = false
    var clicks = 0
    var caption: String?
    var detail: String?
    var keys: [String] = []
    var card: DemoCard?
}

/// A made-up wallpaper, bright enough for glass to show off over.
struct DemoWallpaper: View {
    var body: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                Color(red: 0.07, green: 0.09, blue: 0.24), Color(red: 0.16, green: 0.13, blue: 0.42), Color(red: 0.05, green: 0.25, blue: 0.42),
                Color(red: 0.30, green: 0.12, blue: 0.45), Color(red: 0.12, green: 0.42, blue: 0.62), Color(red: 0.05, green: 0.52, blue: 0.56),
                Color(red: 0.55, green: 0.20, blue: 0.38), Color(red: 0.20, green: 0.22, blue: 0.50), Color(red: 0.04, green: 0.20, blue: 0.30),
            ])
            Circle().fill(Color(red: 1.0, green: 0.55, blue: 0.35).opacity(0.35)).frame(width: 520).blur(radius: 120)
                .offset(x: -420, y: 260)
            Circle().fill(Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.28)).frame(width: 640).blur(radius: 140)
                .offset(x: 460, y: -220)
        }
        .ignoresSafeArea()
    }
}

struct DemoOverlayView: View {
    let state: DemoOverlayState
    let crop: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let card = state.card {
                DemoCardView(card: card)
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .transition(.opacity)
            }
            if let title = state.caption {
                DemoCaption(title: title, detail: state.detail, keys: state.keys)
                    .id(title)
                    .position(x: crop.midX, y: crop.maxY - 78)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
            if state.showPointer {
                DemoPointer(clicks: state.clicks)
                    .position(state.pointer)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: state.card)
        .animation(.easeInOut(duration: 0.3), value: state.caption)
        .animation(.easeInOut(duration: 0.25), value: state.showPointer)
        .ignoresSafeArea()
    }
}

struct DemoCardView: View {
    let card: DemoCard

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.28))
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 168, height: 168)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
                Text(card.title)
                    .font(.system(size: 72, weight: .bold))
                Text(card.subtitle)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                Text(card.footnote)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 6)
            }
            .foregroundStyle(.white)
        }
    }
}

struct DemoCaption: View {
    let title: String
    let detail: String?
    let keys: [String]

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 31, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 20)).foregroundStyle(.white.opacity(0.72))
                }
            }
            if !keys.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                        Text(key)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .frame(minWidth: 40, minHeight: 40)
                            .padding(.horizontal, key.count > 1 ? 10 : 0)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.16)))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: keys)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
    }
}

/// The arrow, with its tip at the view's position, and a ring on each click.
struct DemoPointer: View {
    let clicks: Int
    private static let image = NSCursor.arrow.image
    private static let hotSpot = NSCursor.arrow.hotSpot
    private static let zoom = 1.45

    var body: some View {
        let size = Self.image.size
        ZStack {
            if clicks > 0 { ClickRing().id(clicks) }
            Image(nsImage: Self.image)
                .resizable()
                .frame(width: size.width * Self.zoom, height: size.height * Self.zoom)
                .offset(x: (size.width / 2 - Self.hotSpot.x) * Self.zoom, y: (size.height / 2 - Self.hotSpot.y) * Self.zoom)
        }
        .frame(width: 90, height: 90)
    }
}

struct ClickRing: View {
    @State private var grown = false

    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.9), lineWidth: 3)
            .frame(width: 44, height: 44)
            .scaleEffect(grown ? 1.4 : 0.3)
            .opacity(grown ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.45)) { grown = true } }
    }
}
#endif
