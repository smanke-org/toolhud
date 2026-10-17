import AppKit
import Observation
import ToolHUDKit

/// The lens apps on this Mac, and whether each can take lens actions yet.
///
/// An app takes lens actions once it registers its URL scheme; until then (an older
/// version) ToolHUD presses the feature's default shortcut instead. Our other apps join by
/// declaring `ToolHUDActions` in their Info.plist (see `LensCatalog`).
@Observable
@MainActor
final class LensDirectory {
    static let shared = LensDirectory()

    struct Installed {
        var app: LensApp
        var url: URL
        var version: String
        var supportsURLs: Bool
    }

    /// The built-in apps, whether installed or not, then any other app that declared actions.
    private(set) var apps: [LensApp] = LensCatalog.builtIn
    private(set) var installed: [String: Installed] = [:]

    private init() { refresh() }

    func app(_ bundleID: String) -> LensApp? { apps.first { $0.id == bundleID } }

    /// A Debug build can pretend a lens app isn't installed, to show how Settings handles it.
    private static func debugMissing(_ id: String) -> Bool {
        #if DEBUG
        return id == DebugHooks.missingApp
        #else
        return false
        #endif
    }

    /// The app's page on the developer's site, where it can be downloaded.
    static func webPage(for app: LensApp) -> URL {
        let slug = app.name.lowercased().replacingOccurrences(of: " ", with: "-")
        return URL(string: "https://stevemanke.com/\(slug)/") ?? URL(string: "https://stevemanke.com/")!
    }

    /// Looks again, for when an app was installed or updated while ToolHUD was running.
    func refresh() {
        var found: [String: Installed] = [:]
        var all = LensCatalog.builtIn
        for known in LensCatalog.builtIn {
            if Self.debugMissing(known.id) { continue }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: known.id),
               let entry = Self.read(url, bundleID: known.id) {
                found[known.id] = entry
                all = all.map { $0.id == known.id ? entry.app : $0 }
            }
        }
        // Our other apps in /Applications that describe themselves.
        let folder = URL(fileURLWithPath: "/Applications")
        let bundles = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in bundles where url.pathExtension == "app" {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id.hasPrefix("com.smanke."),
                  id != Bundle.main.bundleIdentifier, found[id] == nil, !Self.debugMissing(id),
                  bundle.object(forInfoDictionaryKey: LensCatalog.infoPlistKey) != nil,
                  let entry = Self.read(url, bundleID: id) else { continue }
            found[id] = entry
            all.append(entry.app)
        }
        installed = found
        apps = all
    }

    private static func read(_ url: URL, bundleID: String) -> Installed? {
        guard let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist")) as? [String: Any] else {
            return nil
        }
        let name = info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        guard let app = LensCatalog.resolve(bundleID: bundleID, name: name, info: info) else { return nil }
        return Installed(app: app, url: url, version: info["CFBundleShortVersionString"] as? String ?? "",
                         supportsURLs: LensCatalog.schemes(in: info).contains(app.scheme))
    }

    /// How a lens button will run, in words for Settings.
    func status(of slot: Slot) -> (text: String, ok: Bool) {
        guard let id = slot.lensApp, let app = app(id) else { return ("Choose an app.", false) }
        guard let featureID = slot.lensFeature, let feature = app.feature(featureID) else {
            return ("Choose what \(app.name) should do.", false)
        }
        guard let entry = installed[id] else {
            return ("\(app.name) isn't installed on this Mac.", false)
        }
        if entry.supportsURLs || LensCatalog.isOpenOnly(featureID) {
            return ("Calls \(app.name) directly, so it keeps working if you change \(app.name)'s shortcuts.", true)
        }
        if let shortcut = feature.shortcut {
            return ("\(app.name) \(entry.version) can't take lens actions yet, so ToolHUD presses its shortcut \(shortcut.display) until you update it.", true)
        }
        return ("\(app.name) \(entry.version) can't take lens actions yet. Update it to use this button.", false)
    }
}
