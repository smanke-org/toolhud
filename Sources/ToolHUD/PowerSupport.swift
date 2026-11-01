import AppKit
import Observation
import ToolHUDKit

// MARK: - The last action

/// What the HUD ran last, for running it again from the HUD's center, Space or
/// `toolhud://repeat`. Kept on this Mac only.
@MainActor
enum LastAction {
    private static let key = "lastAction"
    private static var cached: Slot??

    static var slot: Slot? {
        if let cached { return cached }
        let stored = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Slot.self, from: $0) }
        cached = .some(stored)
        return stored
    }

    static func record(_ slot: Slot) {
        guard slot.mode != .folder else { return }
        cached = .some(slot)
        #if DEBUG
        if DebugHooks.isStaging { return }
        #endif
        UserDefaults.standard.set(try? JSONEncoder().encode(slot), forKey: key)
    }
}

// MARK: - On/off lights

/// Which of our apps' features are on, as the apps report them (see
/// `FeatureStateProtocol`), so the HUD can light those buttons.
@Observable
@MainActor
final class FeatureStates {
    static let shared = FeatureStates()

    /// Bundle identifier → feature id → on.
    private(set) var states: [String: [String: Bool]] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {}

    /// Starts listening, and asks every app to say where it stands.
    func requestRefresh() {
        if observer == nil {
            observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(FeatureStateProtocol.changed), object: nil, queue: .main) { note in
                guard let id = note.object as? String,
                      let reported = note.userInfo?[FeatureStateProtocol.statesKey] as? [String: Bool] else { return }
                MainActor.assumeIsolated { FeatureStates.shared.states[id] = reported }
            }
        }
        // Forgotten first, so an app that has quit since shows no lights; the ones running
        // answer within moments.
        states = [:]
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(FeatureStateProtocol.request), object: nil, userInfo: nil, deliverImmediately: true)
    }

    #if DEBUG
    func debugSet(_ bundleID: String, _ reported: [String: Bool]) { states[bundleID] = reported }
    #endif

    /// Whether the button's feature is on: nil when its app doesn't say, or it isn't an
    /// app's feature at all.
    func isOn(_ slot: Slot) -> Bool? {
        guard slot.mode == .lens, let app = slot.lensApp, let feature = slot.lensFeature else { return nil }
        return states[app]?[feature]
    }
}

// MARK: - Search

/// Something the HUD's search found.
struct SearchResult: Identifiable {
    enum Target {
        case button(Slot)
        case menuItem(bundleID: String, path: String)
    }

    let id: String
    var title: String
    var subtitle: String
    var symbol: String
    var color: SlotColor
    var target: Target
    /// Ranked under buttons of the same score.
    var rank = 0
}

/// Gathers what the search can find: the buttons, every installed app's ToolHUD actions,
/// the menus of the apps in ToolHUD's menu, and the Shortcuts app's shortcuts.
@MainActor
enum SearchSource {
    static func gather(currentRing: [Slot]) -> [SearchResult] {
        let prefs = Preferences.shared
        var results: [SearchResult] = []
        var seen = Set<UUID>()
        let buttons = currentRing + prefs.allButtons
        for slot in buttons + buttons.flatMap({ $0.children ?? [] }) where !seen.contains(slot.id) {
            seen.insert(slot.id)
            if slot.mode == .folder && !prefs.foldersEnabled { continue }
            if slot.mode == .appMenu && !prefs.appMenuButtonsEnabled { continue }
            results.append(SearchResult(id: "b\(slot.id)", title: slot.name, subtitle: "Button · \(slot.sourceName)",
                                        symbol: slot.symbol, color: slot.tint, target: .button(slot), rank: 3))
        }

        let directory = LensDirectory.shared
        // An app's menu often repeats its ToolHUD actions; those show once, as the action.
        var actions = Set<String>()
        for app in directory.apps where directory.installed[app.id] != nil {
            for feature in app.features {
                actions.insert(app.id + "|" + SearchMatch.fold(feature.title))
                results.append(SearchResult(id: "l\(app.id).\(feature.id)", title: feature.title, subtitle: app.name,
                                            symbol: feature.symbol, color: app.color, target: .button(Slot(app, feature.id)),
                                            rank: 2))
            }
        }

        for item in MenuHubHost.shared.searchableItems()
            where !actions.contains(item.bundleID + "|" + SearchMatch.fold(item.title)) {
            results.append(SearchResult(id: "m\(item.bundleID).\(item.path)", title: item.title,
                                        subtitle: (["\(item.appName) menu"] + item.parents).joined(separator: " › "),
                                        symbol: "menubar.rectangle", color: .neutral,
                                        target: .menuItem(bundleID: item.bundleID, path: item.path), rank: 1))
        }
        return results
    }

    static func shortcutResults(_ names: [String]) -> [SearchResult] {
        names.map { name in
            SearchResult(id: "s\(name)", title: name, subtitle: "Shortcut", symbol: ActionMode.shortcut.symbol,
                         color: .neutral,
                         target: .button(Slot(name: name, symbol: ActionMode.shortcut.symbol, mode: .shortcut, shortcutName: name)))
        }
    }

    /// The best matches first; with nothing typed, the buttons in order.
    static func rank(_ all: [SearchResult], query: String) -> [SearchResult] {
        let limit = SearchCardLayout.maxRows
        guard !SearchMatch.fold(query).isEmpty else { return Array(all.prefix(limit)) }
        let scored = all.compactMap { result -> (SearchResult, Int)? in
            let title = SearchMatch.score(query, in: result.title)
            let subtitle = SearchMatch.score(query, in: result.subtitle).map { $0 / 3 }
            guard let best = [title, subtitle].compactMap({ $0 }).max() else { return nil }
            return (result, best * 10 + result.rank)
        }
        // Letters-in-order matches only fill in when nothing matches better.
        let close = scored.filter { $0.1 >= SearchMatch.looseLimit * 10 }
        return Array((close.isEmpty ? scored : close).sorted { $0.1 > $1.1 }.map(\.0).prefix(limit))
    }

    // MARK: Shortcuts

    private static var shortcutNames: [String] = []
    private static var shortcutsLoaded = Date.distantPast

    /// The Shortcuts app's shortcuts, by name, from `shortcuts list`; kept for a few minutes.
    static func loadShortcuts(_ done: @escaping @MainActor ([String]) -> Void) {
        if Date().timeIntervalSince(shortcutsLoaded) < 300 {
            done(shortcutNames)
            return
        }
        Task.detached {
            let names = Self.listShortcuts()
            await MainActor.run {
                shortcutNames = names
                shortcutsLoaded = Date()
                done(names)
            }
        }
    }

    nonisolated static func listShortcuts() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
