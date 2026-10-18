import Foundation

/// A feature a lens app can run on request.
public struct LensFeature: Codable, Hashable, Sendable, Identifiable {
    /// The URL host that runs it: `textlens://capture`.
    public var id: String
    /// As the app's own menu words it: "Capture the same area again".
    public var title: String
    /// What a new button is called: "Capture again".
    public var shortTitle: String
    public var symbol: String
    /// The app's default shortcut for it, used when the installed version can't take a
    /// lens action yet.
    public var shortcut: Shortcut?
    /// Bring the app forward. Off for features that put up their own overlay or panel,
    /// so the app you were using stays in front.
    public var activates: Bool

    public init(id: String, title: String, shortTitle: String? = nil, symbol: String, shortcut: Shortcut? = nil,
                activates: Bool = false) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle ?? title
        self.symbol = symbol
        self.shortcut = shortcut
        self.activates = activates
    }
}

/// One of our apps that ToolHUD knows how to drive.
public struct LensApp: Hashable, Sendable, Identifiable {
    /// The bundle identifier.
    public var id: String
    public var name: String
    /// The URL scheme it registers for lens actions.
    public var scheme: String
    public var color: SlotColor
    public var features: [LensFeature]
    /// Where to get the app when it isn't installed, for apps without a page on the
    /// developer's site yet. Nil means its stevemanke.com page.
    public var downloadURL: URL?

    public init(id: String, name: String, scheme: String, color: SlotColor, features: [LensFeature],
                downloadURL: URL? = nil) {
        self.id = id
        self.name = name
        self.scheme = scheme
        self.color = color
        self.features = features
        self.downloadURL = downloadURL
    }

    public func feature(_ id: String) -> LensFeature? { features.first { $0.id == id } }

    /// `textlens://capture`, with the ToolHUD marker so the app can tell who asked.
    public func url(for featureID: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = featureID
        components.queryItems = [URLQueryItem(name: "source", value: "toolhud")]
        return components.url
    }
}

/// The lens apps and their features.
///
/// An app can also describe itself: a `ToolHUDActions` array in its Info.plist, each entry
/// a dictionary with `id`, `title`, optional `shortTitle`, `symbol`, `activates`. What an
/// installed app declares replaces the built-in list, so a new feature shows up in ToolHUD
/// as soon as the app ships it, and any of our apps can join by adding the key.
public enum LensCatalog {
    public static let infoPlistKey = "ToolHUDActions"

    private static func k(_ code: UInt16, _ key: String) -> Shortcut { .controlOptionCommand(code, key) }

    public static let textLens = LensApp(
        id: "com.smanke.TextLens", name: "TextLens", scheme: "textlens", color: SlotColor(hex: "#5B9BFF")!,
        features: [
            LensFeature(id: "capture", title: "Capture text", symbol: "text.viewfinder", shortcut: k(KeyCode.t, "T")),
            LensFeature(id: "recapture", title: "Capture the same area again", shortTitle: "Capture again",
                        symbol: "arrow.clockwise", shortcut: k(KeyCode.r, "R")),
            LensFeature(id: "qr", title: "Read a QR or bar code", shortTitle: "Read QR", symbol: "qrcode.viewfinder",
                        shortcut: k(KeyCode.d, "D")),
            LensFeature(id: "translate", title: "Capture and translate", shortTitle: "Translate", symbol: "translate",
                        shortcut: k(KeyCode.y, "Y")),
            LensFeature(id: "live-translate", title: "Live translate an area", shortTitle: "Live translate",
                        symbol: "captions.bubble", shortcut: k(KeyCode.u, "U")),
            LensFeature(id: "watch", title: "Watch an area for changes", shortTitle: "Watch area", symbol: "eye",
                        shortcut: k(KeyCode.w, "W")),
            LensFeature(id: "history", title: "Show history", shortTitle: "History", symbol: "clock.arrow.circlepath",
                        shortcut: k(KeyCode.h, "H"), activates: true),
        ])

    public static let clickLens = LensApp(
        id: "com.smanke.ClickLens", name: "ClickLens", scheme: "clicklens", color: SlotColor(hex: "#FF9A4D")!,
        features: [
            LensFeature(id: "spotlight", title: "Spotlight", symbol: "circle.dashed.inset.filled", shortcut: k(KeyCode.l, "L")),
            LensFeature(id: "clicks", title: "Click rings", symbol: "cursorarrow.click.2", shortcut: k(KeyCode.c, "C")),
            LensFeature(id: "keystrokes", title: "Keystrokes", symbol: "keyboard", shortcut: k(KeyCode.k, "K")),
            LensFeature(id: "box", title: "Draw a box", shortTitle: "Draw box", symbol: "rectangle.dashed",
                        shortcut: k(KeyCode.b, "B")),
            LensFeature(id: "arrow", title: "Draw an arrow", shortTitle: "Draw arrow", symbol: "arrow.up.right",
                        shortcut: k(KeyCode.a, "A")),
        ])

    /// PasteLens already answers these URLs (pastelens://quickpaste and the rest).
    public static let pasteLens = LensApp(
        id: "com.smanke.PasteLens", name: "PasteLens", scheme: "pastelens", color: SlotColor(hex: "#B98CFF")!,
        features: [
            LensFeature(id: "quickpaste", title: "Quick Paste", symbol: "list.clipboard",
                        shortcut: Shortcut(keyCode: KeyCode.grave, modifiers: [.control], key: "`")),
            LensFeature(id: "stack", title: "Show the stack", shortTitle: "Paste stack", symbol: "square.stack.3d.up",
                        shortcut: Shortcut(keyCode: KeyCode.v, modifiers: [.control, .shift, .command], key: "V")),
            LensFeature(id: "snippets", title: "Snippets", symbol: "text.badge.plus"),
            LensFeature(id: "open", title: "Open the clipboard history", shortTitle: "Clipboard", symbol: "doc.on.clipboard",
                        activates: true),
        ])

    public static let diskLens = LensApp(
        id: "com.smanke.DiskLens", name: "DiskLens", scheme: "disklens", color: SlotColor(hex: "#3ED9BE")!,
        features: [
            LensFeature(id: "open", title: "Open DiskLens", shortTitle: "Disk space", symbol: "internaldrive", activates: true),
            LensFeature(id: "scan-home", title: "Scan your home folder", shortTitle: "Scan home", symbol: "house",
                        activates: true),
        ])

    /// Needs ExpansionLens 1.0.0 or later, the first version, which answers all of these.
    public static let expansionLens = LensApp(
        id: "com.smanke.ExpansionLens", name: "ExpansionLens", scheme: "expansionlens", color: SlotColor(hex: "#22D3EE")!,
        features: [
            LensFeature(id: "quicksearch", title: "Search snippets", symbol: "magnifyingglass"),
            LensFeature(id: "new", title: "New snippet", symbol: "plus.square", activates: true),
            LensFeature(id: "newfromclipboard", title: "New snippet from the clipboard", shortTitle: "Clip to snippet",
                        symbol: "doc.on.clipboard", activates: true),
            LensFeature(id: "editlast", title: "Edit the last expanded snippet", shortTitle: "Edit last",
                        symbol: "pencil.line", activates: true),
            LensFeature(id: "toggle", title: "Turn expansion on or off", shortTitle: "Expansion on/off",
                        symbol: "power"),
            LensFeature(id: "on", title: "Turn expansion on", shortTitle: "Expansion on", symbol: "play.circle"),
            LensFeature(id: "off", title: "Turn expansion off", shortTitle: "Expansion off", symbol: "pause.circle"),
            LensFeature(id: "settings", title: "ExpansionLens settings", shortTitle: "Expander settings",
                        symbol: "gearshape", activates: true),
        ],
        downloadURL: URL(string: "https://github.com/smanke-org/ExpansionLens/releases/latest"))

    public static let builtIn: [LensApp] = [textLens, clickLens, pasteLens, diskLens, expansionLens]

    public static func app(_ bundleID: String) -> LensApp? { builtIn.first { $0.id == bundleID } }

    /// Whether this feature only opens the app, so it works even without URL support.
    public static func isOpenOnly(_ featureID: String) -> Bool { featureID == "open" }

    /// The lens app and feature whose default shortcut this is, for conflict warnings.
    public static func owner(of shortcut: Shortcut, in apps: [LensApp] = builtIn) -> (app: LensApp, feature: LensFeature)? {
        for app in apps {
            if let feature = app.features.first(where: { $0.shortcut?.sameKeys(as: shortcut) == true }) {
                return (app, feature)
            }
        }
        return nil
    }

    // MARK: - Reading an installed app's Info.plist

    /// The URL schemes an app registers (CFBundleURLTypes › CFBundleURLSchemes).
    public static func schemes(in info: [String: Any]) -> [String] {
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }.map { $0.lowercased() }
    }

    /// The features an app declares under `ToolHUDActions`, or nil if it declares none.
    public static func declaredFeatures(in info: [String: Any]) -> [LensFeature]? {
        guard let entries = info[infoPlistKey] as? [[String: Any]] else { return nil }
        let features = entries.compactMap { entry -> LensFeature? in
            guard let id = entry["id"] as? String, !id.isEmpty, let title = entry["title"] as? String else { return nil }
            return LensFeature(id: id, title: title, shortTitle: entry["shortTitle"] as? String,
                               symbol: entry["symbol"] as? String ?? "circle",
                               activates: entry["activates"] as? Bool ?? false)
        }
        return features.isEmpty ? nil : features
    }

    /// The app as installed: its own declared features (keeping the built-in default
    /// shortcuts, which the plist doesn't carry) or the built-in list. An app we don't know
    /// joins only if it declares features and a scheme.
    public static func resolve(bundleID: String, name: String, info: [String: Any]) -> LensApp? {
        let known = app(bundleID)
        let declared = declaredFeatures(in: info)
        if var known {
            if let declared {
                known.features = declared.map { feature in
                    var merged = feature
                    merged.shortcut = known.feature(feature.id)?.shortcut
                    return merged
                }
            }
            return known
        }
        guard let declared, let scheme = schemes(in: info).first else { return nil }
        return LensApp(id: bundleID, name: name, scheme: scheme, color: .neutral, features: declared)
    }
}
