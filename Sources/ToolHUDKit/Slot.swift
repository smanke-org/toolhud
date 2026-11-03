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

/// What a button does when it's chosen. Each button keeps every kind's settings, so
/// switching back and forth doesn't lose the others.
public enum ActionMode: String, Codable, CaseIterable, Sendable {
    /// Ask a lens app to run one of its features directly, through its URL scheme.
    case lens
    /// Send a key combination.
    case keystroke
    /// Run a shortcut from the Shortcuts app.
    case shortcut
    /// Open an app, a file, a folder or a web address.
    case open
    /// Type a piece of text into the app in front.
    case text
    /// Choose an item from an app's menu bar menus.
    case menuItem
    /// Run an AppleScript or a shell command.
    case script
    /// Run several actions in turn.
    case chain
    /// Open a smaller ring of more buttons. Only while folders are turned on.
    case folder
    /// Show one of our apps' menus at the pointer. Only while app menu buttons are on.
    case appMenu

    public var title: String {
        switch self {
        case .lens: "Lens action"
        case .keystroke: "Keystroke"
        case .shortcut: "Shortcut"
        case .open: "Open"
        case .text: "Type text"
        case .menuItem: "Menu item"
        case .script: "Script"
        case .chain: "Steps"
        case .folder: "Folder"
        case .appMenu: "App menu"
        }
    }

    public var symbol: String {
        switch self {
        case .lens: "app.connected.to.app.below.fill"
        case .keystroke: "keyboard"
        case .shortcut: "square.2.layers.3d"
        case .open: "arrow.up.forward.app"
        case .text: "character.cursor.ibeam"
        case .menuItem: "filemenu.and.selection"
        case .script: "terminal"
        case .chain: "list.number"
        case .folder: "folder"
        case .appMenu: "menubar.rectangle"
        }
    }

    /// Whether a step of a Steps button can be this: not another list of steps, a folder
    /// or a menu, which wait for the user.
    public var canBeStep: Bool {
        switch self {
        case .chain, .folder, .appMenu: false
        default: true
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

/// How a Type text button puts its text in.
public enum TextMethod: String, Codable, CaseIterable, Sendable {
    /// Typed character by character, as if from the keyboard.
    case type
    /// Pasted through the clipboard, which gets its old contents back afterwards. Faster
    /// for long text, and right for apps that drop typed characters.
    case paste

    public var title: String {
        switch self {
        case .type: "Type it"
        case .paste: "Paste it"
        }
    }
}

/// What a Script button runs.
public enum ScriptKind: String, Codable, CaseIterable, Sendable {
    case appleScript, shell

    public var title: String {
        switch self {
        case .appleScript: "AppleScript"
        case .shell: "Shell command"
        }
    }
}

/// One action in a Steps button, and how long to wait before the next.
public struct ChainStep: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var action: Slot
    /// Seconds to wait after this step, 0–10.
    public var delay: Double

    public init(id: UUID = UUID(), action: Slot, delay: Double = ChainStep.defaultDelay) {
        self.id = id
        self.action = action
        self.delay = delay
    }

    public static let defaultDelay = 0.3
    public static let maxDelay = 10.0
    public static let maxSteps = 12

    private enum CodingKeys: String, CodingKey { case id, action, delay }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        action = (try? c.decode(Slot.self, forKey: .action)) ?? .empty()
        delay = min(max((try? c.decode(Double.self, forKey: .delay)) ?? Self.defaultDelay, 0), Self.maxDelay)
    }
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
    /// Where keystrokes, typed text and menu items go.
    public var sendTo: SendTarget
    /// The Shortcuts app shortcut a Shortcut button runs, by name.
    public var shortcutName: String?
    /// What an Open button opens: a web address, or a file, folder or app as a file URL.
    public var openTarget: String?
    /// What a Type text button types, and how.
    public var text: String?
    public var textMethod: TextMethod
    /// A Menu item button's item, menu by menu: ["File", "Export…"].
    public var menuPath: [String]?
    /// What a Script button runs.
    public var script: String?
    public var scriptKind: ScriptKind
    /// A Steps button's actions, in order.
    public var steps: [ChainStep]?
    /// A Folder button's buttons.
    public var children: [Slot]?
    /// The app whose menu an App menu button shows, by bundle identifier and name.
    public var menuApp: String?
    public var menuAppName: String?

    /// The keys a keystroke button presses, including one saved as a single shortcut.
    public var keySequence: KeySequence? {
        keys ?? shortcut.map(KeySequence.init)
    }

    public init(id: UUID = UUID(), name: String, symbol: String, color: SlotColor? = nil, mode: ActionMode,
                lensApp: String? = nil, lensFeature: String? = nil, shortcut: Shortcut? = nil,
                keys: KeySequence? = nil, sendTo: SendTarget = .frontmost, shortcutName: String? = nil,
                openTarget: String? = nil, text: String? = nil, textMethod: TextMethod = .type,
                menuPath: [String]? = nil, script: String? = nil, scriptKind: ScriptKind = .appleScript,
                steps: [ChainStep]? = nil, children: [Slot]? = nil, menuApp: String? = nil, menuAppName: String? = nil) {
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
        self.shortcutName = shortcutName
        self.openTarget = openTarget
        self.text = text
        self.textMethod = textMethod
        self.menuPath = menuPath
        self.script = script
        self.scriptKind = scriptKind
        self.steps = steps
        self.children = children
        self.menuApp = menuApp
        self.menuAppName = menuAppName
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

    /// A folder's buttons as the HUD shows them: at least the minimum, at most the maximum.
    public var folderButtons: [Slot] {
        Array((children ?? []).prefix(DefaultRing.maxCount))
    }

    /// Its own buttons and steps, and theirs, for search and for finding a button by name.
    public var nested: [Slot] {
        let inner = (children ?? []) + (steps ?? []).map(\.action)
        return inner + inner.flatMap(\.nested)
    }

    /// The same button with new identities throughout, so a copy can't be mistaken for the
    /// original by SwiftUI.
    public func freshCopy() -> Slot {
        var copy = self
        copy.id = UUID()
        copy.children = children?.map { $0.freshCopy() }
        copy.steps = steps?.map { ChainStep(action: $0.action.freshCopy(), delay: $0.delay) }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, color, mode, lensApp, lensFeature, shortcut, keys, sendTo
        case shortcutName, openTarget, text, textMethod, menuPath, script, scriptKind, steps, children
        case menuApp, menuAppName
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
        shortcutName = try? c.decodeIfPresent(String.self, forKey: .shortcutName)
        openTarget = try? c.decodeIfPresent(String.self, forKey: .openTarget)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        textMethod = (try? c.decode(TextMethod.self, forKey: .textMethod)) ?? .type
        menuPath = try? c.decodeIfPresent([String].self, forKey: .menuPath)
        script = try? c.decodeIfPresent(String.self, forKey: .script)
        scriptKind = (try? c.decode(ScriptKind.self, forKey: .scriptKind)) ?? .appleScript
        steps = try? c.decodeIfPresent([ChainStep].self, forKey: .steps)
        children = try? c.decodeIfPresent([Slot].self, forKey: .children)
        menuApp = try? c.decodeIfPresent(String.self, forKey: .menuApp)
        menuAppName = try? c.decodeIfPresent(String.self, forKey: .menuAppName)
    }

    /// Only what's set, so buttons saved by this version still read in older ones, and
    /// rings and synced settings stay small.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(lensApp, forKey: .lensApp)
        try c.encodeIfPresent(lensFeature, forKey: .lensFeature)
        try c.encodeIfPresent(shortcut, forKey: .shortcut)
        try c.encodeIfPresent(keys, forKey: .keys)
        try c.encode(sendTo, forKey: .sendTo)
        try c.encodeIfPresent(shortcutName, forKey: .shortcutName)
        try c.encodeIfPresent(openTarget, forKey: .openTarget)
        try c.encodeIfPresent(text, forKey: .text)
        if textMethod != .type { try c.encode(textMethod, forKey: .textMethod) }
        try c.encodeIfPresent(menuPath, forKey: .menuPath)
        try c.encodeIfPresent(script, forKey: .script)
        if scriptKind != .appleScript { try c.encode(scriptKind, forKey: .scriptKind) }
        try c.encodeIfPresent(steps, forKey: .steps)
        try c.encodeIfPresent(children, forKey: .children)
        try c.encodeIfPresent(menuApp, forKey: .menuApp)
        try c.encodeIfPresent(menuAppName, forKey: .menuAppName)
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
        file.slots = file.slots.prefix(DefaultRing.maxCount).map { $0.freshCopy() }
        file.pad = file.pad.map { $0.prefix(DefaultPad.maxCount).map { $0.freshCopy() } }
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
        var copy = slots[index].freshCopy()
        copy.name += " copy"
        slots.insert(copy, at: index + 1)
        slots.removeLast()
        count += 1
    }

    /// Puts a new button at `index` (at most `count`, right after the shown ones), as the
    /// agent command line adds one. The last hidden place makes room, so the list keeps its
    /// length. Does nothing at the maximum, and says so.
    @discardableResult
    public static func insert(_ slot: Slot, at index: Int, slots: inout [Slot], count: inout Int, maxCount: Int) -> Bool {
        guard count < maxCount, count < slots.count else { return false }
        slots.insert(slot, at: min(max(index, 0), count))
        slots.removeLast()
        count += 1
        return true
    }
}

/// The buttons a particular app gets instead of the usual ones, while rings for each app
/// are turned on. Like the usual buttons, the lists keep their full length and the first
/// `count` show.
public struct AppRing: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var name: String
    public var slots: [Slot]
    public var slotCount: Int
    public var padSlots: [Slot]
    public var padCount: Int

    public init(bundleID: String, name: String, slots: [Slot], slotCount: Int, padSlots: [Slot], padCount: Int) {
        self.bundleID = bundleID
        self.name = name
        self.slots = AppRing.filled(slots, to: DefaultRing.maxCount, from: DefaultRing.slots)
        self.slotCount = min(max(slotCount, DefaultRing.minCount), DefaultRing.maxCount)
        self.padSlots = AppRing.filled(padSlots, to: DefaultPad.maxCount, from: DefaultPad.slots)
        self.padCount = min(max(padCount, DefaultPad.minCount), DefaultPad.maxCount)
    }

    /// A new app's ring starts as a copy of the usual one, to change from there.
    public static func copying(bundleID: String, name: String, slots: [Slot], slotCount: Int,
                               padSlots: [Slot], padCount: Int) -> AppRing {
        AppRing(bundleID: bundleID, name: name, slots: slots.map { $0.freshCopy() }, slotCount: slotCount,
                padSlots: padSlots.map { $0.freshCopy() }, padCount: padCount)
    }

    public var visibleSlots: [Slot] { Array(slots.prefix(slotCount)) }
    public var visiblePadSlots: [Slot] { Array(padSlots.prefix(padCount)) }

    /// `list` cut or topped up with `spare`'s buttons to `length`.
    static func filled(_ list: [Slot], to length: Int, from spare: [Slot]) -> [Slot] {
        var list = Array(list.prefix(length))
        while list.count < length { list.append(list.count < spare.count ? spare[list.count] : .empty()) }
        return list
    }

    private enum CodingKeys: String, CodingKey { case bundleID, name, slots, slotCount, padSlots, padCount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bundleID: try c.decode(String.self, forKey: .bundleID),
                  name: (try? c.decode(String.self, forKey: .name)) ?? "App",
                  slots: (try? c.decode([Slot].self, forKey: .slots)) ?? DefaultRing.slots,
                  slotCount: (try? c.decode(Int.self, forKey: .slotCount)) ?? DefaultRing.defaultCount,
                  padSlots: (try? c.decode([Slot].self, forKey: .padSlots)) ?? DefaultPad.slots,
                  padCount: (try? c.decode(Int.self, forKey: .padCount)) ?? DefaultPad.defaultCount)
    }
}

/// Which ring a name asks for, as in `toolhud://show?ring=Safari`: an app's ring by app
/// name or bundle identifier, or a folder button by its name. Case doesn't matter.
public enum RingLookup {
    public enum Match: Equatable, Sendable {
        case usual
        case app(String)
        case folder(Slot)
    }

    public static func find(_ name: String, appRings: [AppRing], buttons: [Slot]) -> Match? {
        let wanted = name.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return .usual }
        func same(_ a: String) -> Bool { a.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if same("default") || same("usual") || same("all apps") { return .usual }
        if let ring = appRings.first(where: { same($0.name) || same($0.bundleID) }) { return .app(ring.bundleID) }
        let folders = (buttons + buttons.flatMap(\.nested)).filter { $0.mode == .folder }
        if let folder = folders.first(where: { same($0.name) }) { return .folder(folder) }
        return nil
    }
}
