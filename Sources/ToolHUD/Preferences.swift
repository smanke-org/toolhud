import AppKit
import Observation
import SwiftUI
import ToolHUDKit

/// Every setting, persisted to UserDefaults as it changes.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    // MARK: General
    /// Quitting asks first, so a stray ⌘Q doesn't stop the HUD.
    var confirmQuit: Bool = true { didSet { save(confirmQuit, "confirmQuit") } }

    // MARK: Buttons
    /// Always twelve: the first `slotCount` are on the HUD, and the rest wait there so that
    /// lowering the count and raising it again brings the same buttons back.
    var slots: [Slot] = DefaultRing.slots { didSet { saveCodable(slots, "slots") } }
    var slotCount: Int = DefaultRing.defaultCount { didSet { save(slotCount, "slotCount") } }

    // MARK: Button pad
    /// Extra buttons in a tray beside the look. Like `slots`, always eight, of which the
    /// first `padCount` show.
    var padEnabled: Bool = false { didSet { save(padEnabled, "padEnabled") } }
    var padPosition: PadPosition = .right { didSet { save(padPosition.rawValue, "padPosition") } }
    var padSlots: [Slot] = DefaultPad.slots { didSet { saveCodable(padSlots, "padSlots") } }
    var padCount: Int = DefaultPad.defaultCount { didSet { save(padCount, "padCount") } }

    // MARK: Features
    /// Press / in the HUD to search every button, app feature and app menu. On by default.
    var searchEnabled: Bool = true { didSet { save(searchEnabled, "searchEnabled") } }
    /// Click the HUD's center, or press Space, to run the last action again.
    var repeatLastEnabled: Bool = false { didSet { save(repeatLastEnabled, "repeatLastEnabled") } }
    /// Folder buttons, which open a smaller ring of more buttons.
    var foldersEnabled: Bool = false { didSet { save(foldersEnabled, "foldersEnabled") } }
    /// A different ring for particular apps.
    var appRingsEnabled: Bool = false { didSet { save(appRingsEnabled, "appRingsEnabled") } }
    var appRings: [AppRing] = [] { didSet { saveCodable(appRings, "appRings") } }
    /// App menu buttons, which show one of our apps' menus at the pointer.
    var appMenuButtonsEnabled: Bool = false { didSet { save(appMenuButtonsEnabled, "appMenuButtonsEnabled") } }
    /// Buttons light up while the feature they run is on.
    var stateLightsEnabled: Bool = false { didSet { save(stateLightsEnabled, "stateLightsEnabled") } }

    // MARK: Appearance
    var visualization: Visualization = .halo { didSet { save(visualization.rawValue, "visualization") } }
    /// How solid the HUD's surfaces are, 0.2–1. Labels stay fully opaque.
    var opacity: Double = Defaults.opacity { didSet { save(opacity, "opacity") } }
    var size: HUDSize = .medium { didSet { save(size.rawValue, "hudSize") } }
    var anchor: HUDAnchor = .pointer { didSet { save(anchor.rawValue, "hudAnchor") } }
    var playSound: Bool = false { didSet { save(playSound, "playSound") } }
    var haptics: Bool = true { didSet { save(haptics, "haptics") } }

    // MARK: Triggers
    var hotKey: Shortcut? = .defaultHUD { didSet { saveCodable(hotKey, "hotKey") } }
    var hotKeyMode: HotKeyMode = .hold { didSet { save(hotKeyMode.rawValue, "hotKeyMode") } }
    var mouseTrigger: MouseTrigger = .optionRight { didSet { save(mouseTrigger.rawValue, "mouseTrigger") } }
    /// Seconds the right button must be held for "Hold right-click".
    var holdDelay: Double = Defaults.holdDelay { didSet { save(holdDelay, "holdDelay") } }
    var doubleTapKey: DoubleTapKey = .off { didSet { save(doubleTapKey.rawValue, "doubleTapKey") } }
    var hotCorner: HotCorner = .off { didSet { save(hotCorner.rawValue, "hotCorner") } }
    /// Seconds the pointer must rest in the corner.
    var cornerDelay: Double = Defaults.cornerDelay { didSet { save(cornerDelay, "cornerDelay") } }

    enum Defaults {
        static let opacity = 0.8
        static let holdDelay = 0.3
        static let cornerDelay = 0.3
    }

    /// The buttons on the HUD now.
    var visibleSlots: [Slot] { Array(slots.prefix(slotCount)) }

    /// The pad's buttons now, whether or not the pad is on.
    var visiblePadSlots: [Slot] { Array(padSlots.prefix(padCount)) }

    /// The ring for the app with this bundle identifier, while rings for each app are on.
    func appRing(for bundleID: String?) -> AppRing? {
        guard appRingsEnabled, let bundleID else { return nil }
        return appRings.first { $0.bundleID == bundleID }
    }

    /// Every button there is, every app's ring included, for search and for finding a folder
    /// by name.
    var allButtons: [Slot] {
        let lists = [visibleSlots, padEnabled ? visiblePadSlots : []]
            + (appRingsEnabled ? appRings.flatMap { [$0.visibleSlots, padEnabled ? $0.visiblePadSlots : []] } : [])
        return lists.flatMap { $0 }
    }

    /// Every key this class writes, so a reset can clear them all.
    static let keys = [
        "slots", "slotCount", "visualization", "opacity", "hudSize", "hudAnchor", "playSound", "haptics",
        "hotKey", "hotKeyMode", "mouseTrigger", "holdDelay", "padEnabled", "padPosition", "padSlots", "padCount",
        "confirmQuit", "searchEnabled", "repeatLastEnabled", "foldersEnabled", "appRingsEnabled", "appRings",
        "appMenuButtonsEnabled", "stateLightsEnabled", "doubleTapKey", "hotCorner", "cornerDelay",
    ]

    @ObservationIgnored private var loading = false

    private init() { load() }

    /// Puts every setting back to how a new install starts. Where the app appears,
    /// open-at-login, sync and update checks are left alone.
    func resetToDefaults() {
        for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) }
        load()
        SettingsSync.shared.localDidChange()
    }

    /// Replaces the buttons with an imported ring.
    func adopt(_ ring: RingFile) {
        var imported = ring.slots
        slotCount = min(max(imported.count, DefaultRing.minCount), DefaultRing.maxCount)
        // Pad with the defaults, so the count can still go up to twelve.
        let spare = DefaultRing.slots
        while imported.count < DefaultRing.maxCount { imported.append(spare[imported.count]) }
        slots = imported
        if let viz = ring.visualization { visualization = viz }
        if var pad = ring.pad {
            padCount = min(max(pad.count, DefaultPad.minCount), DefaultPad.maxCount)
            let spare = DefaultPad.slots
            while pad.count < DefaultPad.maxCount { pad.append(spare[pad.count]) }
            padSlots = pad
            if let position = ring.padPosition { padPosition = position }
            padEnabled = true
        }
    }

    /// Every setting's current value, in the form UserDefaults stores it, defaults included.
    /// iCloud gets the whole set, so a Mac adopting it never mistakes a setting that is
    /// merely at its default for one that is missing.
    var snapshot: [String: Any] {
        func data<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }
        return [
            "slots": data(slots), "slotCount": slotCount, "visualization": visualization.rawValue,
            "opacity": opacity, "hudSize": size.rawValue, "hudAnchor": anchor.rawValue,
            "playSound": playSound, "haptics": haptics, "hotKey": data(hotKey),
            "hotKeyMode": hotKeyMode.rawValue, "mouseTrigger": mouseTrigger.rawValue, "holdDelay": holdDelay,
            "padEnabled": padEnabled, "padPosition": padPosition.rawValue, "padSlots": data(padSlots), "padCount": padCount,
            "confirmQuit": confirmQuit, "searchEnabled": searchEnabled, "repeatLastEnabled": repeatLastEnabled,
            "foldersEnabled": foldersEnabled, "appRingsEnabled": appRingsEnabled, "appRings": data(appRings),
            "appMenuButtonsEnabled": appMenuButtonsEnabled, "stateLightsEnabled": stateLightsEnabled,
            "doubleTapKey": doubleTapKey.rawValue, "hotCorner": hotCorner.rawValue, "cornerDelay": cornerDelay,
        ]
    }

    /// Re-reads every setting after another Mac's settings were written into UserDefaults.
    func reload() { load() }

    private func load() {
        loading = true
        defer { loading = false }
        let d = UserDefaults.standard
        func double(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) as? Double ?? fallback }
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
        func codable<T: Decodable>(_ key: String, _ fallback: T) -> T {
            guard let data = d.data(forKey: key) else { return fallback }
            return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
        }

        var stored: [Slot] = codable("slots", DefaultRing.slots)
        let spare = DefaultRing.slots
        while stored.count < DefaultRing.maxCount { stored.append(spare[stored.count]) }
        slots = Array(stored.prefix(DefaultRing.maxCount))
        let count = d.object(forKey: "slotCount") as? Int ?? DefaultRing.defaultCount
        slotCount = min(max(count, DefaultRing.minCount), DefaultRing.maxCount)

        var storedPad: [Slot] = codable("padSlots", DefaultPad.slots)
        let sparePad = DefaultPad.slots
        while storedPad.count < DefaultPad.maxCount { storedPad.append(sparePad[storedPad.count]) }
        padSlots = Array(storedPad.prefix(DefaultPad.maxCount))
        let storedPadCount = d.object(forKey: "padCount") as? Int ?? DefaultPad.defaultCount
        padCount = min(max(storedPadCount, DefaultPad.minCount), DefaultPad.maxCount)
        padEnabled = bool("padEnabled", false)
        padPosition = PadPosition(rawValue: d.string(forKey: "padPosition") ?? "") ?? .right

        visualization = Visualization(rawValue: d.string(forKey: "visualization") ?? "") ?? .halo
        opacity = min(max(double("opacity", Defaults.opacity), 0.2), 1)
        size = HUDSize(rawValue: d.string(forKey: "hudSize") ?? "") ?? .medium
        anchor = HUDAnchor(rawValue: d.string(forKey: "hudAnchor") ?? "") ?? .pointer
        playSound = bool("playSound", false)
        haptics = bool("haptics", true)

        hotKey = codable("hotKey", Shortcut.defaultHUD)
        hotKeyMode = HotKeyMode(rawValue: d.string(forKey: "hotKeyMode") ?? "") ?? .hold
        mouseTrigger = MouseTrigger(rawValue: d.string(forKey: "mouseTrigger") ?? "") ?? .optionRight
        holdDelay = min(max(double("holdDelay", Defaults.holdDelay), 0.15), 0.8)

        confirmQuit = bool("confirmQuit", true)

        searchEnabled = bool("searchEnabled", true)
        repeatLastEnabled = bool("repeatLastEnabled", false)
        foldersEnabled = bool("foldersEnabled", false)
        appRingsEnabled = bool("appRingsEnabled", false)
        appRings = codable("appRings", [AppRing]())
        appMenuButtonsEnabled = bool("appMenuButtonsEnabled", false)
        stateLightsEnabled = bool("stateLightsEnabled", false)
        doubleTapKey = DoubleTapKey(rawValue: d.string(forKey: "doubleTapKey") ?? "") ?? .off
        hotCorner = HotCorner(rawValue: d.string(forKey: "hotCorner") ?? "") ?? .off
        cornerDelay = min(max(double("cornerDelay", Defaults.cornerDelay), 0), 1.5)
    }

    private func save(_ value: Any, _ key: String) {
        guard !loading else { return }
        store(value as? NSObject, key)
    }

    private func saveCodable<T: Encodable>(_ value: T, _ key: String) {
        guard !loading else { return }
        store((try? JSONEncoder().encode(value)) as NSObject?, key)
    }

    /// Writes only real changes, and reports them for iCloud sync. SwiftUI controls write
    /// their current value back when settings arrive from another Mac; counting those as
    /// edits would send the same settings back and forth between Macs forever.
    private func store(_ value: NSObject?, _ key: String) {
        #if DEBUG
        // Staging runs share the installed app's settings; they may change them in memory only.
        if DebugHooks.isStaging { return }
        #endif
        let defaults = UserDefaults.standard
        if let old = defaults.object(forKey: key) as? NSObject, let value, old.isEqual(value) { return }
        defaults.set(value, forKey: key)
        SettingsSync.shared.localDidChange()
    }
}

extension SlotColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .white
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }
}

extension Slot {
    /// Its own color, else its lens app's.
    @MainActor var tint: SlotColor {
        color ?? lensApp.flatMap { LensDirectory.shared.app($0)?.color } ?? .neutral
    }

    @MainActor var appName: String? {
        lensApp.flatMap { LensDirectory.shared.app($0)?.name }
    }

    @MainActor var summary: String {
        switch mode {
        case .lens:
            let feature = lensApp.flatMap { LensDirectory.shared.app($0) }?.feature(lensFeature ?? "")
            return [appName, feature?.title].compactMap { $0 }.joined(separator: " · ")
        case .keystroke:
            let target: String
            switch sendTo {
            case .frontmost: target = ""
            case .app(_, let name): target = " → \(name)"
            }
            return "Keystroke \(keySequence?.display ?? "(none set)")\(target)"
        case .shortcut:
            return shortcutName.map { "Runs the shortcut “\($0)”" } ?? "No shortcut chosen"
        case .open:
            return openTarget.map { "Opens \(Slot.openTargetName($0))" } ?? "Nothing to open yet"
        case .text:
            let t = (text ?? "").replacingOccurrences(of: "\n", with: " ")
            return t.isEmpty ? "No text yet" : "Types “\(t.count > 40 ? t.prefix(40) + "…" : t)”"
        case .menuItem:
            return menuPath.map { MenuPath.display($0) } ?? "No menu item chosen"
        case .script:
            return "\(scriptKind.title)\((script ?? "").isEmpty ? " (empty)" : "")"
        case .chain:
            let n = steps?.count ?? 0
            return n == 1 ? "1 step" : "\(n) steps"
        case .folder:
            let n = children?.count ?? 0
            return n == 1 ? "Folder of 1 button" : "Folder of \(n) buttons"
        case .appMenu:
            return "\(menuAppName ?? "An app")’s menu"
        }
    }

    /// What the readout and the Settings list show under a button's name: its app, or the
    /// kind of action.
    @MainActor var sourceName: String {
        switch mode {
        case .lens: appName ?? "Lens action"
        case .keystroke: "Keystroke"
        case .menuItem, .text:
            if case .app(_, let name) = sendTo { "\(mode.title) · \(name)" } else { mode.title }
        case .appMenu: menuAppName ?? mode.title
        default: mode.title
        }
    }

    /// A file's name, or a web address as typed.
    static func openTargetName(_ target: String) -> String {
        if target.hasPrefix("/") || target.hasPrefix("~") {
            return FileManager.default.displayName(atPath: (target as NSString).expandingTildeInPath)
                .replacingOccurrences(of: ".app", with: "")
        }
        guard let url = URL(string: target), url.isFileURL else { return target }
        return FileManager.default.displayName(atPath: url.path)
    }
}
