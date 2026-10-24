import Foundation

/// A color stored as plain sRGB numbers, so it round-trips through JSON and UserDefaults.
public struct SlotColor: Codable, Hashable, Sendable {
    public var red: Double, green: Double, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// From "#5B9BFF" or "5B9BFF".
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    public var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// The swatches offered in Settings, besides "the app's color" and a custom pick.
    public static let swatches: [(name: String, color: SlotColor)] = [
        ("Blue", SlotColor(hex: "#5B9BFF")!), ("Orange", SlotColor(hex: "#FF9A4D")!),
        ("Purple", SlotColor(hex: "#B98CFF")!), ("Teal", SlotColor(hex: "#3ED9BE")!),
        ("Pink", SlotColor(hex: "#FF6FAE")!), ("Yellow", SlotColor(hex: "#FFD24D")!),
    ]

    /// For a button with no lens app and no color of its own.
    public static let neutral = SlotColor(hex: "#A9B4C8")!
}

/// What a button does when it's chosen. Each button keeps both kinds of settings, so
/// switching back and forth doesn't lose the other one.
public enum ActionMode: String, Codable, CaseIterable, Sendable {
    /// Ask a lens app to run one of its features directly, through its URL scheme.
    case lens
    /// Send a key combination.
    case keystroke

    public var title: String {
        switch self {
        case .lens: "Lens action"
        case .keystroke: "Keystroke"
        }
    }
}

/// Where a keystroke button sends its keys.
public enum SendTarget: Codable, Hashable, Sendable {
    /// The app that was in front when the HUD opened.
    case frontmost
    /// A particular app, brought forward (and opened if needed) first.
    case app(bundleID: String, name: String)
}

/// One button on the HUD.
public struct Slot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol name.
    public var symbol: String
    /// nil uses the lens app's color.
    public var color: SlotColor?
    public var mode: ActionMode
    /// The lens app's bundle identifier and the feature's identifier.
    public var lensApp: String?
    public var lensFeature: String?
    /// A lens feature's default shortcut, pressed when its app is too old for lens actions;
    /// before key sequences, also what a keystroke button pressed.
    public var shortcut: Shortcut?
    /// What a keystroke button presses. nil on buttons saved before sequences.
    public var keys: KeySequence?
    public var sendTo: SendTarget

    /// The keys a keystroke button presses, including one saved as a single shortcut.
    public var keySequence: KeySequence? {
        keys ?? shortcut.map(KeySequence.init)
    }

    public init(id: UUID = UUID(), name: String, symbol: String, color: SlotColor? = nil, mode: ActionMode,
                lensApp: String? = nil, lensFeature: String? = nil, shortcut: Shortcut? = nil,
                keys: KeySequence? = nil, sendTo: SendTarget = .frontmost) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.mode = mode
        self.lensApp = lensApp
        self.lensFeature = lensFeature
        self.shortcut = shortcut
        self.keys = keys
        self.sendTo = sendTo
    }

    /// A button that runs a catalog feature, with that feature's shortcut kept as the
    /// keystroke alternative.
    public init(_ app: LensApp, _ featureID: String) {
        let feature = app.feature(featureID)
        self.init(name: feature?.shortTitle ?? featureID, symbol: feature?.symbol ?? "circle", mode: .lens,
                  lensApp: app.id, lensFeature: featureID, shortcut: feature?.shortcut)
    }

    /// An unused button.
    public static func empty() -> Slot {
        Slot(name: "New button", symbol: "plus.circle", mode: .keystroke)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, color, mode, lensApp, lensFeature, shortcut, keys, sendTo
    }

    /// Lenient: a field a later version adds, or one an imported file leaves out, falls
    /// back to a default instead of making the whole ring unreadable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Button"
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? "circle"
        color = try? c.decodeIfPresent(SlotColor.self, forKey: .color)
        mode = (try? c.decode(ActionMode.self, forKey: .mode)) ?? .keystroke
        lensApp = try? c.decodeIfPresent(String.self, forKey: .lensApp)
        lensFeature = try? c.decodeIfPresent(String.self, forKey: .lensFeature)
        shortcut = try? c.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        keys = try? c.decodeIfPresent(KeySequence.self, forKey: .keys)
        sendTo = (try? c.decode(SendTarget.self, forKey: .sendTo)) ?? .frontmost
    }
}

public enum DefaultRing {
    /// Twelve buttons: the first `defaultCount` show on a new install, and the rest are
    /// there when the count goes up.
    public static var slots: [Slot] {
        let c = LensCatalog.self
        return [
            Slot(c.textLens, "capture"), Slot(c.clickLens, "spotlight"), Slot(c.pasteLens, "quickpaste"),
            Slot(c.textLens, "translate"), Slot(c.clickLens, "clicks"), Slot(c.diskLens, "open"),
            Slot(c.textLens, "qr"), Slot(c.clickLens, "arrow"), Slot(c.textLens, "live-translate"),
            Slot(c.clickLens, "keystrokes"), Slot(c.textLens, "history"), Slot(c.clickLens, "box"),
        ]
    }

    public static let defaultCount = 8
    public static let maxCount = 12
    public static let minCount = 2
}

/// A ring saved to a file, for Export and Import in Settings.
public struct RingFile: Codable, Sendable {
    public var format = "ToolHUD ring"
    public var version = 1
    public var visualization: Visualization?
    public var slots: [Slot]
    /// The button pad, when it's turned on. Older rings have none.
    public var pad: [Slot]?
    public var padPosition: PadPosition?

    public init(visualization: Visualization?, slots: [Slot], pad: [Slot]? = nil, padPosition: PadPosition? = nil) {
        self.visualization = visualization
        self.slots = slots
        self.pad = pad
        self.padPosition = padPosition
    }

    public static let fileExtension = "toolhudring"

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public enum ReadError: LocalizedError {
        case notARing, empty
        public var errorDescription: String? {
            switch self {
            case .notARing: "That file isn't a ToolHUD ring."
            case .empty: "That ring has no buttons."
            }
        }
    }

    /// Reads a file written by `encoded()`. Buttons get new identities, so importing the
    /// same ring twice can't produce two buttons that SwiftUI treats as one.
    public static func decode(_ data: Data) throws -> RingFile {
        guard var file = try? JSONDecoder().decode(RingFile.self, from: data), file.format == "ToolHUD ring" else {
            throw ReadError.notARing
        }
        guard !file.slots.isEmpty else { throw ReadError.empty }
        func fresh(_ slot: Slot) -> Slot {
            var copy = slot
            copy.id = UUID()
            return copy
        }
        file.slots = file.slots.prefix(DefaultRing.maxCount).map(fresh)
        file.pad = file.pad.map { $0.prefix(DefaultPad.maxCount).map(fresh) }
        if file.pad?.isEmpty == true { file.pad = nil }
        return file
    }
}

/// Edits to a button list that keeps its full length (`slots` holds every place, the first
/// `count` show), as the right-click menu in Settings › Buttons makes them.
public enum SlotListEdit {
    /// Removes the button at `index`. An empty button takes the free place at the end, so
    /// the list keeps its length. Does nothing at the minimum.
    public static func delete(at index: Int, slots: inout [Slot], count: inout Int, minCount: Int) {
        guard count > minCount, slots.indices.contains(index), index < count else { return }
        slots.remove(at: index)
        slots.append(.empty())
        count -= 1
    }

    /// Puts a copy of the button at `index` right after it, named "<name> copy". The last
    /// hidden place makes room, so the list keeps its length. Does nothing at the maximum.
    public static func duplicate(at index: Int, slots: inout [Slot], count: inout Int, maxCount: Int) {
        guard count < maxCount, count < slots.count, slots.indices.contains(index), index < count else { return }
        var copy = slots[index]
        copy.id = UUID()
        copy.name += " copy"
        slots.insert(copy, at: index + 1)
        slots.removeLast()
        count += 1
    }
}
