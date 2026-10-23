import AppKit
import Observation
import SwiftUI
import ToolHUDKit

/// Every setting, persisted to UserDefaults as it changes.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    // MARK: Buttons
    /// Always twelve: the first `slotCount` are on the HUD, and the rest wait there so that
    /// lowering the count and raising it again brings the same buttons back.
    var slots: [Slot] = DefaultRing.slots { didSet { saveCodable(slots, "slots") } }
    var slotCount: Int = DefaultRing.defaultCount { didSet { save(slotCount, "slotCount") } }

    // MARK: Button pad
    /// Extra buttons in a tray beside the Halo. Like `slots`, always eight, of which the
    /// first `padCount` show.
    var padEnabled: Bool = false { didSet { save(padEnabled, "padEnabled") } }
    var padPosition: PadPosition = .right { didSet { save(padPosition.rawValue, "padPosition") } }
    var padSlots: [Slot] = DefaultPad.slots { didSet { saveCodable(padSlots, "padSlots") } }
    var padCount: Int = DefaultPad.defaultCount { didSet { save(padCount, "padCount") } }

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

    enum Defaults {
        static let opacity = 0.8
        static let holdDelay = 0.3
    }

    /// The buttons on the HUD now.
    var visibleSlots: [Slot] { Array(slots.prefix(slotCount)) }

    /// The pad's buttons now, whether or not the pad is on.
    var visiblePadSlots: [Slot] { Array(padSlots.prefix(padCount)) }

    /// Every key this class writes, so a reset can clear them all.
    static let keys = [
        "slots", "slotCount", "visualization", "opacity", "hudSize", "hudAnchor", "playSound", "haptics",
        "hotKey", "hotKeyMode", "mouseTrigger", "holdDelay", "padEnabled", "padPosition", "padSlots", "padCount",
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
            return "Keystroke \(shortcut?.display ?? "(none set)")\(target)"
        }
    }
}
