import Foundation

// MARK: - Type to search

/// How well a search term matches a title, for the HUD's search. Higher is better; nil is no
/// match. A title that starts with the term beats one with a word that starts with it,
/// which beats one that merely contains it; letters in order ("cpt" for "Capture text")
/// still count, a little.
public enum SearchMatch {
    /// Scores below this are letters-in-order matches.
    public static let looseLimit = 101

    public static func score(_ query: String, in title: String) -> Int? {
        let q = fold(query), t = fold(title)
        guard !q.isEmpty else { return 0 }
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 800 - min(t.count, 200) }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 600 - min(t.count, 200) }
        // Every word of the query starts a word of the title, in any order: "text cap".
        let parts = q.split(separator: " ")
        if parts.count > 1, parts.allSatisfy({ part in words.contains { $0.hasPrefix(part) } }) {
            return 500 - min(t.count, 200)
        }
        if t.contains(q) { return 400 - min(t.count, 200) }
        // The letters in order, the first at the start of a word.
        let letters = Array(q.filter { $0 != " " })
        guard let first = letters.first, words.contains(where: { $0.first == first }) else { return nil }
        var i = 0
        for ch in t where i < letters.count && ch == letters[i] { i += 1 }
        return i == letters.count ? 100 - min(t.count, 90) : nil
    }

    /// Lowercased, without accents, with "..." read as "…".
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "...", with: "…")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Where the search card and its rows are, in the HUD's own coordinates (points from its
/// center, y downward), so the drawing and the clicks agree.
public enum SearchCardLayout {
    public static let width = 380.0
    public static let fieldHeight = 46.0
    public static let rowHeight = 38.0
    public static let maxRows = 8
    public static let footerHeight = 26.0

    public static func height(rows: Int) -> Double {
        fieldHeight + Double(max(rows, 1)) * rowHeight + footerHeight
    }

    /// The card's top-left corner.
    public static func origin(rows: Int) -> HUDPoint {
        HUDPoint(-width / 2, -height(rows: rows) / 2)
    }

    /// The result row under `point`, if any.
    public static func row(at point: HUDPoint, rows: Int) -> Int? {
        let o = origin(rows: rows)
        let x = point.x - o.x, y = point.y - o.y - fieldHeight
        guard x >= 0, x <= width, y >= 0 else { return nil }
        let row = Int(y / rowHeight)
        return row < rows ? row : nil
    }

    public static func contains(_ point: HUDPoint, rows: Int) -> Bool {
        let o = origin(rows: rows)
        return point.x >= o.x && point.x <= o.x + width && point.y >= o.y && point.y <= o.y + height(rows: rows)
    }
}

// MARK: - Menu items

/// A Menu item button's path, as typed in Settings: "File > Export…".
public enum MenuPath {
    public static let separator = " > "

    public static func parse(_ text: String) -> [String] {
        text.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func display(_ path: [String]) -> String { path.joined(separator: separator) }

    /// A menu's own title against the one the button names: case, accents and "..."
    /// against "…" don't matter.
    public static func matches(_ title: String, _ wanted: String) -> Bool {
        SearchMatch.fold(title) == SearchMatch.fold(wanted)
    }
}

// MARK: - Repeat the last action

/// How near the HUD's center a click must be to run the last action again.
public enum RepeatTarget {
    public static func radius(for visualization: Visualization) -> Double {
        switch visualization {
        case .commandDeck, .hive, .glassPills: 34
        default: 52
        }
    }

    public static func contains(_ point: HUDPoint, in visualization: Visualization) -> Bool {
        point.length <= radius(for: visualization)
    }
}

// MARK: - More ways to open the HUD

/// A modifier key that opens the HUD when pressed twice quickly on its own.
public enum DoubleTapKey: String, Codable, CaseIterable, Sendable {
    case off, command, option, control, shift

    public var title: String {
        switch self {
        case .off: "Off"
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        }
    }

    public var modifier: KeyModifiers? {
        switch self {
        case .off: nil
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
}

/// Spots a modifier pressed and let go twice within `window` seconds, with nothing else
/// pressed in between, so holding it for a shortcut never counts.
public struct DoubleTapDetector: Sendable {
    public var key: KeyModifiers
    public var window: Double
    /// The longest a press may be held and still count as a tap.
    public var maxHold = 0.35

    private var downAt: Double?
    private var lastTapAt: Double?

    public init(key: KeyModifiers, window: Double = 0.4) {
        self.key = key
        self.window = window
    }

    /// The modifiers held now, at `time` seconds. True on the second tap's release.
    public mutating func flagsChanged(_ held: KeyModifiers, at time: Double) -> Bool {
        if held == key {
            downAt = time
            return false
        }
        guard held.isEmpty, let down = downAt else {
            // Another modifier joined in: it's a shortcut, not a tap.
            reset()
            return false
        }
        downAt = nil
        guard time - down <= maxHold else {
            lastTapAt = nil
            return false
        }
        if let last = lastTapAt, time - last <= window {
            lastTapAt = nil
            return true
        }
        lastTapAt = time
        return false
    }

    /// Any other key or click in between.
    public mutating func interrupt() { reset() }

    private mutating func reset() {
        downAt = nil
        lastTapAt = nil
    }
}

/// A screen corner that opens the HUD when the pointer rests in it.
public enum HotCorner: String, Codable, CaseIterable, Sendable {
    case off, topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .off: "Off"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    /// Whether `point` is in this corner of `frame`, both with y upward (as AppKit's screen
    /// coordinates run), within `slack` points.
    public func contains(x: Double, y: Double, minX: Double, minY: Double, maxX: Double, maxY: Double,
                         slack: Double = 3) -> Bool {
        let left = x <= minX + slack, right = x >= maxX - 1 - slack
        let bottom = y <= minY + slack, top = y >= maxY - 1 - slack
        switch self {
        case .off: return false
        case .topLeft: return top && left
        case .topRight: return top && right
        case .bottomLeft: return bottom && left
        case .bottomRight: return bottom && right
        }
    }
}

// MARK: - On/off lights

/// How our apps tell ToolHUD which of their features are on, so the HUD can light those
/// buttons. Each app posts a distributed notification whenever a feature turns on or off,
/// with its bundle identifier as the object and `[feature id: Bool]` under `statesKey`;
/// ToolHUD posts `request` when it wants every app to post again.
public enum FeatureStateProtocol {
    public static let changed = "com.smanke.ToolHUD.featureStates"
    public static let request = "com.smanke.ToolHUD.featureStatesRequest"
    public static let statesKey = "states"
}
