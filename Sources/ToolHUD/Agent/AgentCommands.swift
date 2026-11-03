import AppKit
import ToolHUDKit

// ToolHUD's agent commands. Each `run` uses the same code as Settings › Buttons, the HUD and
// the toolhud:// links: Preferences for the buttons (saved and synced as Settings saves them),
// HUDController to show, hide and run, LensDirectory for what lens buttons can do.
//
// A button is found by the first characters of its id, in the usual ring, the button pad, or
// an app's ring. Only the buttons that show count: the hidden places past the count are spares.

@MainActor
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(
            name: "status",
            summary: "Version, whether the HUD is open, its look, how many buttons, which features are on.",
            example: "toolhud status --json",
            readOnly: true,
            run: { _ in status() }),

        AgentCommand(
            name: "buttons list",
            summary: "The buttons that show, in order: id, name, kind and what each does.",
            params: [
                .init(name: "ring", help: "\"usual\" (the default), an app's ring by app name or bundle id, or \"all\""),
                .init(name: "place", help: "ring, pad or both (the default)"),
                .init(name: "search", help: "only buttons whose name or action contains this"),
                .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                .init(name: "offset", kind: .integer, help: "skip this many, from nextOffset"),
            ],
            example: "toolhud buttons list --ring Safari --json",
            readOnly: true,
            run: { args in try listButtons(args) }),

        AgentCommand(
            name: "buttons show",
            summary: "One button in full: its kind's settings, a folder's buttons, a Steps button's steps.",
            params: [.init(name: "id", required: true, positional: true, help: "the button's id (any unique start)")],
            example: "toolhud buttons show 3f2a9c1e --json",
            readOnly: true,
            run: { args in try showButton(args) }),

        AgentCommand(
            name: "buttons add",
            summary: "Add a button after the ones that show (or at --position). Folders, Steps and app menu buttons are made in Settings.",
            params: [.init(name: "kind", required: true, help: "lens, keystroke, shortcut, open, text, menu-item or script")]
                + editParams + placeParams + [.init(name: "position", kind: .integer, help: "1 for the first place; default after the last")],
            example: "toolhud buttons add --kind open --url https://example.com --name Docs --symbol safari --json",
            run: { args in try addButton(args) }),

        AgentCommand(
            name: "buttons update",
            summary: "Change a button: its name, symbol, color, kind, or its kind's settings.",
            params: [.init(name: "id", required: true, positional: true, help: "the button's id"),
                     .init(name: "kind", help: "lens, keystroke, shortcut, open, text, menu-item or script")] + editParams,
            example: "toolhud buttons update 3f2a9c1e --name \"Save all\" --keys S --modifiers command,option --json",
            run: { args in try updateButton(args) }),

        AgentCommand(
            name: "buttons duplicate",
            summary: "Put a copy of a button right after it, named \"<name> copy\".",
            params: [.init(name: "id", required: true, positional: true, help: "the button's id")],
            example: "toolhud buttons duplicate 3f2a9c1e --json",
            run: { args in try duplicateButton(args) }),

        AgentCommand(
            name: "buttons delete",
            summary: "Remove a button; the rest move up. Settings › Buttons can't bring it back.",
            params: [.init(name: "id", required: true, positional: true, help: "the button's id")],
            example: "toolhud buttons delete 3f2a9c1e --yes --json",
            destructive: true,
            run: { args in try deleteButton(args) }),

        AgentCommand(
            name: "buttons run",
            summary: "Run a button as clicking it in the HUD does. It may press keys, type, open apps or run a script.",
            params: [.init(name: "id", required: true, positional: true, help: "the button's id")],
            example: "toolhud buttons run 3f2a9c1e --json",
            run: { args in try runButton(args) }),

        AgentCommand(
            name: "rings list",
            summary: "The usual ring and each app's ring, with how many buttons each shows.",
            example: "toolhud rings list --json",
            readOnly: true,
            run: { _ in listRings() }),

        AgentCommand(
            name: "features list",
            summary: "What lens buttons can run: our apps' features, and whether each app is installed.",
            params: [.init(name: "app", help: "one app, by name or bundle id"),
                     .init(name: "limit", kind: .integer, help: "at most this many (default 50)"),
                     .init(name: "offset", kind: .integer, help: "skip this many, from nextOffset")],
            example: "toolhud features list --app TextLens --json",
            readOnly: true,
            run: { args in try listFeatures(args) }),

        AgentCommand(
            name: "hud show",
            summary: "Open the HUD in the middle of the screen, or an app's ring or a folder by name.",
            params: [.init(name: "ring", help: "an app's ring or a folder button, by name")],
            example: "toolhud hud show --ring Safari --json",
            run: { args in try showHUD(args) }),

        AgentCommand(
            name: "hud hide",
            summary: "Close the HUD if it's open.",
            example: "toolhud hud hide --json",
            run: { _ in hideHUD() }),

        AgentCommand(
            name: "hud repeat",
            summary: "Run the last action again, as clicking the HUD's center does.",
            example: "toolhud hud repeat --json",
            run: { _ in try repeatLast() }),

        AgentCommand(
            name: "look set",
            summary: "Change the HUD's look: " + Visualization.allCases.map(\.rawValue).joined(separator: ", ") + ".",
            params: [.init(name: "look", required: true, positional: true, help: "a look's name, like halo or orbit")],
            example: "toolhud look set orbit --json",
            run: { args in try setLook(args) }),

        AgentCommand(
            name: "activity show",
            summary: "How many actions ToolHUD ran on this Mac: today, the last 7 and 30 days, and in all.",
            example: "toolhud activity show --json",
            readOnly: true,
            run: { _ in activity() }),

        AgentCommand(
            name: "settings open",
            summary: "Open Settings, on a pane: " + SettingsPane.allCases.map(\.rawValue).joined(separator: ", ") + ".",
            params: [.init(name: "pane", help: "the pane to show")],
            example: "toolhud settings open --pane buttons --json",
            run: { args in try openSettings(args) }),
    ]

    /// What `buttons add` and `buttons update` can set.
    private static let editParams: [AgentCommand.Param] = [
        .init(name: "name", help: "the label under the button"),
        .init(name: "symbol", help: "an SF Symbol name, like star or safari"),
        .init(name: "color", help: "#5B9BFF, a swatch (blue, orange, purple, teal, pink, yellow), or app for its app's color"),
        .init(name: "app", help: "lens: the app, by name or bundle id (see `toolhud features list`)"),
        .init(name: "feature", help: "lens: the feature's id or title"),
        .init(name: "keys", help: "keystroke: ⇧⌘S, ⌘K ⌘S (K then S), or as typed in Settings: letters, ↩ ⇥ ⎋ ← → ↑ ↓, [F5], [Space]"),
        .init(name: "modifiers", help: "keystroke: command, option, control, shift (comma list), or none"),
        .init(name: "send-to", help: "keystroke, text, menu-item: an app by name or bundle id, or front for the app in front"),
        .init(name: "shortcut", help: "shortcut: the name of a shortcut in the Shortcuts app"),
        .init(name: "url", help: "open: a web address"),
        .init(name: "file", kind: .path, help: "open: an app, file or folder"),
        .init(name: "text", help: "text: what to type"),
        .init(name: "text-method", help: "text: type (default) or paste"),
        .init(name: "menu", help: "menu-item: the item, menu by menu, like \"File > Export…\""),
        .init(name: "script", help: "script: the AppleScript or shell command"),
        .init(name: "script-kind", help: "script: applescript (default) or shell"),
    ]

    private static let placeParams: [AgentCommand.Param] = [
        .init(name: "ring", help: "\"usual\" (the default), or an app's ring by app name or bundle id"),
        .init(name: "place", help: "ring (the default) or pad"),
    ]

    // MARK: Finding buttons

    /// Where a button lives: which ring (nil for the usual one), the ring or the pad, which place.
    struct Location {
        var ring: String?
        var pad: Bool
        var index: Int
    }

    /// The button lists Settings › Buttons edits, read and written through Preferences.
    struct ButtonList {
        var slots: [Slot]
        var count: Int
        var pad: Bool
        var limits: ClosedRange<Int> {
            pad ? DefaultPad.minCount...DefaultPad.maxCount : DefaultRing.minCount...DefaultRing.maxCount
        }
    }

    private static var prefs: Preferences { Preferences.shared }

    private static func list(ring: String?, pad: Bool) -> ButtonList {
        if let ring, let app = prefs.appRings.first(where: { $0.bundleID == ring }) {
            return pad ? ButtonList(slots: app.padSlots, count: app.padCount, pad: true)
                : ButtonList(slots: app.slots, count: app.slotCount, pad: false)
        }
        return pad ? ButtonList(slots: prefs.padSlots, count: prefs.padCount, pad: true)
            : ButtonList(slots: prefs.slots, count: prefs.slotCount, pad: false)
    }

    private static func store(_ list: ButtonList, ring: String?) {
        if let ring, let i = prefs.appRings.firstIndex(where: { $0.bundleID == ring }) {
            if list.pad {
                prefs.appRings[i].padSlots = list.slots
                prefs.appRings[i].padCount = list.count
            } else {
                prefs.appRings[i].slots = list.slots
                prefs.appRings[i].slotCount = list.count
            }
            return
        }
        if list.pad {
            prefs.padSlots = list.slots
            prefs.padCount = list.count
        } else {
            prefs.slots = list.slots
            prefs.slotCount = list.count
        }
    }

    /// Every ring there is: nil for the usual one, then each app's by bundle id.
    private static var rings: [String?] { [nil] + prefs.appRings.map(\.bundleID) }

    private static func ringName(_ ring: String?) -> String {
        ring.flatMap { id in prefs.appRings.first { $0.bundleID == id }?.name } ?? "usual"
    }

    /// "usual", or an app's ring by name or bundle id.
    private static func ring(named name: String?) throws -> String? {
        guard let name, !name.isEmpty else { return nil }
        switch RingLookup.find(name, appRings: prefs.appRings, buttons: []) {
        case .app(let id): return id
        case .usual: return nil
        default:
            let names = prefs.appRings.map(\.name)
            throw AgentError.notFound("no ring called \"\(name)\". Rings: usual\(names.isEmpty ? "" : ", " + names.joined(separator: ", ")). Run `toolhud rings list`")
        }
    }

    private static func place(_ raw: String?, allowBoth: Bool) throws -> [Bool] {
        switch (raw ?? (allowBoth ? "both" : "ring")).lowercased() {
        case "ring": return [false]
        case "pad": return [true]
        case "both" where allowBoth: return [false, true]
        default: throw AgentError.usage("--place must be ring\(allowBoth ? ", pad or both" : " or pad"), not \"\(raw ?? "")\"")
        }
    }

    private static func shortID(_ slot: Slot) -> String {
        String(slot.id.uuidString.lowercased().prefix(8))
    }

    private static func find(_ id: String) throws -> (slot: Slot, at: Location) {
        let wanted = id.lowercased()
        guard wanted.count >= 2 else { throw AgentError.usage("an id needs at least 2 characters. Run `toolhud buttons list`") }
        var hits: [(Slot, Location)] = []
        for ring in rings {
            for pad in [false, true] {
                let list = list(ring: ring, pad: pad)
                for (i, slot) in list.slots.prefix(list.count).enumerated()
                where slot.id.uuidString.lowercased().hasPrefix(wanted) {
                    hits.append((slot, Location(ring: ring, pad: pad, index: i)))
                }
            }
        }
        guard let first = hits.first else {
            throw AgentError.notFound("no button with id \(id). Run `toolhud buttons list --ring all`")
        }
        guard hits.count == 1 else { throw AgentError.usage("\(hits.count) buttons start with \(id). Give more of the id") }
        return first
    }

    // MARK: Output

    private static func summary(_ slot: Slot, at location: Location) -> JSONObject {
        [
            "id": shortID(slot), "name": slot.name, "kind": kindName(slot.mode), "does": slot.summary,
            "symbol": slot.symbol, "ring": ringName(location.ring), "place": location.pad ? "pad" : "ring",
            "position": location.pad ? DefaultPad.keyLetters[location.index] : String(location.index + 1),
        ]
    }

    private static func detail(_ slot: Slot) -> JSONObject {
        var out: JSONObject = [
            "id": shortID(slot), "name": slot.name, "kind": kindName(slot.mode), "does": slot.summary,
            "symbol": slot.symbol, "color": slot.color?.hex ?? "app",
        ]
        switch slot.mode {
        case .lens:
            out["app"] = slot.lensApp ?? ""
            out["appName"] = slot.appName ?? ""
            out["feature"] = slot.lensFeature ?? ""
            out["ready"] = LensDirectory.shared.status(of: slot).ok
            out["status"] = LensDirectory.shared.status(of: slot).text
        case .keystroke:
            out["keys"] = slot.keySequence?.display ?? ""
            out["sendTo"] = target(slot.sendTo)
        case .shortcut:
            out["shortcut"] = slot.shortcutName ?? ""
        case .open:
            out["target"] = slot.openTarget ?? ""
        case .text:
            out["text"] = slot.text ?? ""
            out["textMethod"] = slot.textMethod.rawValue
            out["sendTo"] = target(slot.sendTo)
        case .menuItem:
            out["menu"] = slot.menuPath.map(MenuPath.display) ?? ""
            out["sendTo"] = target(slot.sendTo)
        case .script:
            out["script"] = slot.script ?? ""
            out["scriptKind"] = slot.scriptKind == .shell ? "shell" : "applescript"
        case .chain:
            out["steps"] = (slot.steps ?? []).map { step -> JSONObject in
                ["name": step.action.name, "kind": kindName(step.action.mode), "does": step.action.summary, "delay": step.delay]
            }
        case .folder:
            out["buttons"] = (slot.children ?? []).map { child -> JSONObject in
                ["name": child.name, "kind": kindName(child.mode), "does": child.summary]
            }
        case .appMenu:
            out["app"] = slot.menuApp ?? ""
            out["appName"] = slot.menuAppName ?? ""
        }
        return out
    }

    private static func target(_ target: SendTarget) -> String {
        switch target {
        case .frontmost: "front"
        case .app(let id, let name): "\(name) (\(id))"
        }
    }

    private static func kindName(_ mode: ActionMode) -> String {
        switch mode {
        case .menuItem: "menu-item"
        case .chain: "steps"
        case .appMenu: "app-menu"
        default: mode.rawValue
        }
    }

    private static func page<T>(_ items: [T], _ args: Args) throws -> (items: ArraySlice<T>, extra: JSONObject) {
        let limit = try args.int("limit", default: 50), offset = try args.int("offset", default: 0)
        guard limit > 0, offset >= 0 else { throw AgentError.usage("--limit must be above 0 and --offset 0 or more") }
        let slice = items.dropFirst(offset).prefix(limit)
        var extra: JSONObject = ["total": items.count]
        if offset + slice.count < items.count { extra["nextOffset"] = offset + slice.count }
        return (slice, extra)
    }

    // MARK: Commands

    private static func status() -> JSONObject {
        let log = ActivityStore.shared.log
        var out: JSONObject = [
            "version": AgentCLI.version,
            "hudShowing": HUDController.shared.isShowing,
            "look": prefs.visualization.rawValue,
            "buttons": prefs.slotCount,
            "padOn": prefs.padEnabled,
            "padButtons": prefs.padCount,
            "appRings": prefs.appRings.count,
            "features": [
                "search": prefs.searchEnabled, "repeatLast": prefs.repeatLastEnabled, "folders": prefs.foldersEnabled,
                "appRings": prefs.appRingsEnabled, "appMenuButtons": prefs.appMenuButtonsEnabled,
                "stateLights": prefs.stateLightsEnabled,
            ],
            "shortcut": prefs.hotKey?.display ?? "none",
            "mouseTrigger": prefs.mouseTrigger.rawValue,
            "accessibilityAllowed": AccessibilityTrust.shared.isTrusted,
            "actionsToday": log.days[ActivityLog.key(for: Date())] ?? 0,
            "testCopy": AgentSocket.isTestRun,
        ]
        if let last = LastAction.slot { out["lastAction"] = last.name }
        return out
    }

    private static func listButtons(_ args: Args) throws -> JSONObject {
        let ringArg = args.string("ring")
        let chosen: [String?] = ringArg?.lowercased() == "all" ? rings : [try ring(named: ringArg)]
        let places = try place(args.string("place"), allowBoth: true)
        let search = args.string("search")?.lowercased()
        var items: [JSONObject] = []
        for ring in chosen {
            for pad in places {
                let list = list(ring: ring, pad: pad)
                for (i, slot) in list.slots.prefix(list.count).enumerated() {
                    if let search, !"\(slot.name) \(slot.summary)".lowercased().contains(search) { continue }
                    items.append(summary(slot, at: Location(ring: ring, pad: pad, index: i)))
                }
            }
        }
        let paged = try page(items, args)
        return paged.extra.merging(["buttons": Array(paged.items), "padOn": prefs.padEnabled]) { a, _ in a }
    }

    private static func showButton(_ args: Args) throws -> JSONObject {
        let (slot, at) = try find(args.required("id"))
        return detail(slot).merging(summary(slot, at: at)) { a, _ in a }
    }

    private static func addButton(_ args: Args) throws -> JSONObject {
        let ring = try ring(named: args.string("ring"))
        let pad = try place(args.string("place"), allowBoth: false)[0]
        let mode = try mode(args.required("kind"))
        guard ![.folder, .chain, .appMenu].contains(mode) else {
            throw AgentError.invalid("make folder, Steps and app menu buttons in ToolHUD Settings › Buttons (`toolhud settings open --pane buttons`)")
        }
        var slot = Slot.empty()
        try apply(args, mode: mode, to: &slot)
        if slot.symbol == Slot.empty().symbol { slot.symbol = mode.symbol }
        var list = list(ring: ring, pad: pad)
        let position = try args.int("position", default: list.count + 1)
        guard position >= 1 else { throw AgentError.usage("--position starts at 1") }
        guard SlotListEdit.insert(slot, at: position - 1, slots: &list.slots, count: &list.count, maxCount: list.limits.upperBound) else {
            throw AgentError.invalid("the \(pad ? "pad" : "ring") already has \(list.limits.upperBound) buttons, the most it can. Delete one first")
        }
        store(list, ring: ring)
        let index = list.slots.firstIndex { $0.id == slot.id } ?? 0
        return detail(slot).merging(summary(slot, at: Location(ring: ring, pad: pad, index: index))) { a, _ in a }
    }

    private static func updateButton(_ args: Args) throws -> JSONObject {
        let (old, at) = try find(args.required("id"))
        var slot = old
        let mode = try args.string("kind").map(mode) ?? old.mode
        if mode != old.mode, [.folder, .chain, .appMenu].contains(mode) {
            throw AgentError.invalid("make folder, Steps and app menu buttons in ToolHUD Settings › Buttons (`toolhud settings open --pane buttons`)")
        }
        try apply(args, mode: mode, to: &slot)
        var list = list(ring: at.ring, pad: at.pad)
        list.slots[at.index] = slot
        if slot != old { store(list, ring: at.ring) }
        var out = detail(slot).merging(summary(slot, at: at)) { a, _ in a }
        out["changed"] = slot != old
        return out
    }

    private static func duplicateButton(_ args: Args) throws -> JSONObject {
        let (slot, at) = try find(args.required("id"))
        var list = list(ring: at.ring, pad: at.pad)
        guard list.count < list.limits.upperBound else {
            throw AgentError.invalid("the \(at.pad ? "pad" : "ring") already has \(list.limits.upperBound) buttons, the most it can")
        }
        SlotListEdit.duplicate(at: at.index, slots: &list.slots, count: &list.count, maxCount: list.limits.upperBound)
        store(list, ring: at.ring)
        let copy = list.slots[at.index + 1]
        return summary(copy, at: Location(ring: at.ring, pad: at.pad, index: at.index + 1))
            .merging(["copyOf": shortID(slot)]) { a, _ in a }
    }

    private static func deleteButton(_ args: Args) throws -> JSONObject {
        let (slot, at) = try find(args.required("id"))
        var list = list(ring: at.ring, pad: at.pad)
        guard list.count > list.limits.lowerBound else {
            throw AgentError.invalid("the \(at.pad ? "pad" : "ring") has only \(list.limits.lowerBound) buttons, the fewest it can. Change this one instead")
        }
        var out = summary(slot, at: at)
        guard args.confirmed else {
            out["deleted"] = false
            out["hint"] = "would delete “\(slot.name)” from the \(ringName(at.ring)) \(at.pad ? "pad" : "ring"). Add --yes to delete it"
            return out
        }
        SlotListEdit.delete(at: at.index, slots: &list.slots, count: &list.count, minCount: list.limits.lowerBound)
        store(list, ring: at.ring)
        out["deleted"] = true
        return out
    }

    private static func runButton(_ args: Args) throws -> JSONObject {
        let (slot, at) = try find(args.required("id"))
        if slot.mode == .folder, !prefs.foldersEnabled {
            throw AgentError.invalid("folders are turned off. Turn them on in ToolHUD Settings › Features")
        }
        if slot.mode == .appMenu, !prefs.appMenuButtonsEnabled {
            throw AgentError.invalid("app menu buttons are turned off. Turn them on in ToolHUD Settings › Features")
        }
        if slot.mode == .lens, !LensDirectory.shared.status(of: slot).ok {
            throw AgentError.invalid(LensDirectory.shared.status(of: slot).text)
        }
        HUDController.shared.runChosen(slot)
        // Counted like a click in the HUD; a test copy keeps away from Activity's iCloud sync.
        if !AgentSocket.isTestRun { ActivityStore.shared.record() }
        return summary(slot, at: at).merging(["ran": true]) { a, _ in a }
    }

    private static func listRings() -> JSONObject {
        var items: [JSONObject] = [[
            "name": "usual", "app": "", "buttons": prefs.slotCount, "padButtons": prefs.padCount, "inUse": true,
        ]]
        for ring in prefs.appRings {
            items.append(["name": ring.name, "app": ring.bundleID, "buttons": ring.slotCount, "padButtons": ring.padCount,
                          "inUse": prefs.appRingsEnabled])
        }
        return ["rings": items, "appRingsOn": prefs.appRingsEnabled, "padOn": prefs.padEnabled, "total": items.count]
    }

    private static func listFeatures(_ args: Args) throws -> JSONObject {
        let directory = LensDirectory.shared
        directory.refresh()
        var apps = directory.apps
        if let wanted = args.string("app") { apps = [try lensApp(wanted)] }
        var items: [JSONObject] = []
        for app in apps {
            let installed = directory.installed[app.id]
            for feature in app.features {
                items.append(["app": app.id, "appName": app.name, "feature": feature.id, "title": feature.title,
                              "installed": installed != nil])
            }
        }
        let paged = try page(items, args)
        return paged.extra.merging(["features": Array(paged.items)]) { a, _ in a }
    }

    private static func showHUD(_ args: Args) throws -> JSONObject {
        guard !prefs.visibleSlots.isEmpty else { throw AgentError.invalid("the ring has no buttons") }
        var match: RingLookup.Match?
        if let name = args.string("ring"), !name.isEmpty {
            match = RingLookup.find(name, appRings: prefs.appRingsEnabled ? prefs.appRings : [],
                                    buttons: prefs.foldersEnabled ? prefs.allButtons : [])
            guard match != nil else {
                throw AgentError.notFound("ToolHUD has no ring or folder called “\(name)”. Run `toolhud rings list`")
            }
        }
        // As the toolhud://show link does: next turn of the run loop, mid-screen.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { HUDController.shared.show(atScreenCenter: true, ring: match) }
        }
        return ["shown": true, "ring": args.string("ring") ?? "usual"]
    }

    private static func hideHUD() -> JSONObject {
        let was = HUDController.shared.isShowing
        HUDController.shared.dismiss()
        return ["hidden": true, "changed": was]
    }

    private static func repeatLast() throws -> JSONObject {
        guard let slot = LastAction.slot else { throw AgentError.invalid("nothing has run yet to run again") }
        HUDController.shared.repeatLast()
        return ["ran": true, "name": slot.name, "does": slot.summary]
    }

    private static func setLook(_ args: Args) throws -> JSONObject {
        let raw = try args.required("look")
        func same(_ a: String) -> Bool {
            a.replacingOccurrences(of: " ", with: "").caseInsensitiveCompare(raw.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")) == .orderedSame
        }
        guard let look = Visualization.allCases.first(where: { same($0.rawValue) || same($0.title) }) else {
            throw AgentError.usage("no look called \"\(raw)\". Looks: " + Visualization.allCases.map(\.rawValue).joined(separator: ", "))
        }
        let changed = prefs.visualization != look
        prefs.visualization = look
        return ["look": look.rawValue, "title": look.title, "changed": changed]
    }

    private static func activity() -> JSONObject {
        let log = ActivityStore.shared.log
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func since(_ days: Int) -> Int {
            log.total(since: calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today)
        }
        return ["today": since(1), "last7Days": since(7), "last30Days": since(30), "lifetime": log.lifetime,
                "firstDay": log.firstDay ?? ""]
    }

    private static func openSettings(_ args: Args) throws -> JSONObject {
        var pane: SettingsPane?
        if let raw = args.string("pane") {
            guard let found = SettingsPane.allCases.first(where: { $0.rawValue == raw.lowercased() }) else {
                throw AgentError.usage("no pane called \"\(raw)\". Panes: " + SettingsPane.allCases.map(\.rawValue).joined(separator: ", "))
            }
            pane = found
        }
        SettingsWindow.shared.show(pane)
        return ["opened": true, "pane": pane?.rawValue ?? ""]
    }

    // MARK: Editing a button

    private static func mode(_ raw: String) throws -> ActionMode {
        let names: [String: ActionMode] = [
            "lens": .lens, "keystroke": .keystroke, "shortcut": .shortcut, "open": .open, "text": .text,
            "menu-item": .menuItem, "menuitem": .menuItem, "script": .script,
            "steps": .chain, "folder": .folder, "app-menu": .appMenu,
        ]
        guard let mode = names[raw.lowercased()] else {
            throw AgentError.usage("--kind must be lens, keystroke, shortcut, open, text, menu-item or script, not \"\(raw)\"")
        }
        return mode
    }

    private static func lensApp(_ wanted: String) throws -> LensApp {
        let apps = LensDirectory.shared.apps
        if let app = apps.first(where: { $0.id.caseInsensitiveCompare(wanted) == .orderedSame
            || $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) { return app }
        throw AgentError.notFound("no app called \"\(wanted)\". Apps: " + apps.map(\.name).joined(separator: ", ")
                                  + ". Run `toolhud features list`")
    }

    /// Sets what the options give, the way the editor in Settings › Buttons does.
    private static func apply(_ args: Args, mode: ActionMode, to slot: inout Slot) throws {
        let fields: [ActionMode: [String]] = [
            .lens: ["app", "feature"], .keystroke: ["keys", "modifiers", "send-to"], .shortcut: ["shortcut"],
            .open: ["url", "file"], .text: ["text", "text-method", "send-to"], .menuItem: ["menu", "send-to"],
            .script: ["script", "script-kind"],
        ]
        let allowed = fields[mode] ?? []
        for name in fields.values.flatMap({ $0 }) where args.string(name) != nil && !allowed.contains(name) {
            throw AgentError.usage("--\(name) isn't for \(kindName(mode)) buttons. Run `toolhud help buttons add`")
        }
        let renamed = args.string("name") != nil
        // A name or symbol nobody chose follows the new kind, as in Settings.
        if mode != slot.mode {
            if slot.symbol == "plus.circle" || slot.symbol == slot.mode.symbol { slot.symbol = mode.symbol }
            slot.mode = mode
        }

        switch mode {
        case .lens:
            let app = try args.string("app").map(lensApp) ?? slot.lensApp.flatMap { LensDirectory.shared.app($0) }
            guard let app else { throw AgentError.usage("missing --app. Run `toolhud features list` for apps and features") }
            let wanted = args.string("feature") ?? (app.id == slot.lensApp ? slot.lensFeature : nil) ?? app.features.first?.id ?? ""
            guard let feature = app.features.first(where: { $0.id == wanted || $0.title.caseInsensitiveCompare(wanted) == .orderedSame
                || $0.shortTitle.caseInsensitiveCompare(wanted) == .orderedSame }) else {
                throw AgentError.notFound("\(app.name) has no feature \"\(wanted)\". Features: "
                                          + app.features.map(\.id).joined(separator: ", "))
            }
            let previous = slot.lensApp.flatMap { LensDirectory.shared.app($0) }?.feature(slot.lensFeature ?? "")
            let fresh = Slot(app, feature.id)
            if previous == nil || slot.name == previous?.shortTitle || slot.name == "New button" { slot.name = fresh.name }
            if previous == nil || slot.symbol == previous?.symbol || slot.symbol == ActionMode.lens.symbol { slot.symbol = fresh.symbol }
            slot.lensApp = app.id
            slot.lensFeature = feature.id
            if slot.shortcut == nil || previous?.id != feature.id { slot.shortcut = feature.shortcut }
        case .keystroke:
            var modifiers = try args.string("modifiers").map(parseModifiers) ?? slot.keySequence?.modifiers ?? []
            if var text = args.string("keys") ?? (args.string("modifiers") != nil ? slot.keySequence?.text : nil) {
                // "⇧⌘S" or "⌘K ⌘S", as menus write shortcuts: the symbols are the modifiers, held
                // for every key, and the spaces between keys only separate them.
                let symbols = "⌃⌥⇧⌘"
                if text.contains(where: { symbols.contains($0) }) {
                    let held = try parseModifiers(String(text.filter { symbols.contains($0) }))
                    modifiers = args.string("modifiers") == nil ? held : modifiers.union(held)
                    var inBrackets = false
                    text = String(text.filter { c in
                        if c == "[" { inBrackets = true } else if c == "]" { inBrackets = false }
                        return !symbols.contains(c) && (c != " " || inBrackets)
                    })
                }
                let parsed = KeySequence.parse(text, modifiers: modifiers, lookup: KeyboardLayout.key(for:))
                guard parsed.unknown.isEmpty else {
                    throw AgentError.usage("no key types \(parsed.unknown.joined(separator: " ")). Write special keys as ↩ ⇥ ⎋ ⌫ ← → ↑ ↓ or in brackets, like [F5] or [Space]")
                }
                guard !parsed.sequence.keys.isEmpty else { throw AgentError.usage("--keys is empty") }
                slot.keys = parsed.sequence
            }
            guard slot.keySequence != nil else { throw AgentError.usage("missing --keys. Example: --keys S --modifiers command,shift") }
            if !renamed, slot.name == "New button", let keys = slot.keySequence { slot.name = keys.display }
        case .shortcut:
            if let name = args.string("shortcut") {
                if !renamed, slot.name == "New button" || slot.name == slot.shortcutName { slot.name = name }
                slot.shortcutName = name
            }
            guard slot.shortcutName != nil else { throw AgentError.usage("missing --shortcut, a shortcut's name in the Shortcuts app") }
        case .open:
            if args.string("url") != nil, args.string("file") != nil { throw AgentError.usage("give --url or --file, not both") }
            if let url = args.string("url") {
                guard let parsed = URL(string: url), parsed.scheme != nil else {
                    throw AgentError.usage("--url must be a full address, like https://example.com")
                }
                if !renamed, slot.name == "New button" || slot.openTarget.map(Slot.openTargetName) == slot.name {
                    slot.name = parsed.host ?? url
                }
                slot.openTarget = url
            }
            if let file = args.string("file") {
                guard file.hasPrefix("/") else { throw AgentError.usage("--file must be an absolute path") }
                guard FileManager.default.fileExists(atPath: file) else { throw AgentError.notFound("nothing at \(file)") }
                if !renamed, slot.name == "New button" || slot.openTarget.map(Slot.openTargetName) == slot.name {
                    slot.name = Slot.openTargetName(file)
                }
                slot.openTarget = file
            }
            guard slot.openTarget != nil else { throw AgentError.usage("missing --url or --file") }
        case .text:
            if let text = args.string("text") { slot.text = text }
            if let method = args.string("text-method") {
                guard let value = TextMethod(rawValue: method.lowercased()) else {
                    throw AgentError.usage("--text-method must be type or paste")
                }
                slot.textMethod = value
            }
            guard !(slot.text ?? "").isEmpty else { throw AgentError.usage("missing --text") }
            if !renamed, slot.name == "New button" { slot.name = "Type text" }
        case .menuItem:
            if let menu = args.string("menu") {
                let path = MenuPath.parse(menu)
                guard path.count >= 2 else { throw AgentError.usage("--menu needs a menu and an item, like \"File > Export…\"") }
                slot.menuPath = path
                if !renamed, slot.name == "New button" { slot.name = path.last ?? slot.name }
            }
            guard slot.menuPath != nil else { throw AgentError.usage("missing --menu, like \"File > Export…\"") }
        case .script:
            if let script = args.string("script") { slot.script = script }
            if let kind = args.string("script-kind") {
                switch kind.lowercased() {
                case "applescript": slot.scriptKind = .appleScript
                case "shell": slot.scriptKind = .shell
                default: throw AgentError.usage("--script-kind must be applescript or shell")
                }
            }
            guard !(slot.script ?? "").isEmpty else { throw AgentError.usage("missing --script") }
            if !renamed, slot.name == "New button" { slot.name = slot.scriptKind.title }
        case .chain, .folder, .appMenu:
            break
        }

        if let sendTo = args.string("send-to") { slot.sendTo = try sendTarget(sendTo) }
        if let name = args.string("name") {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AgentError.usage("--name can't be empty") }
            slot.name = trimmed
        }
        if let symbol = args.string("symbol") {
            guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
                throw AgentError.usage("there's no SF Symbol called \"\(symbol)\"")
            }
            slot.symbol = symbol
        }
        if let color = args.string("color") { slot.color = try parseColor(color) }
    }

    private static func parseModifiers(_ raw: String) throws -> KeyModifiers {
        var modifiers: KeyModifiers = []
        let names: [String: KeyModifiers] = [
            "command": .command, "cmd": .command, "⌘": .command, "option": .option, "opt": .option, "alt": .option,
            "⌥": .option, "control": .control, "ctrl": .control, "⌃": .control, "shift": .shift, "⇧": .shift,
        ]
        let parts = raw.split(whereSeparator: { ",+ ".contains($0) }).map { $0.lowercased() }
        for part in parts where part != "none" {
            if let found = names[part] {
                modifiers.insert(found)
            } else if part.allSatisfy({ "⌘⌥⌃⇧".contains($0) }) {
                for c in part { modifiers.insert(names[String(c)]!) }
            } else {
                throw AgentError.usage("--modifiers takes command, option, control and shift, not \"\(part)\"")
            }
        }
        return modifiers
    }

    private static func parseColor(_ raw: String) throws -> SlotColor? {
        if raw.lowercased() == "app" { return nil }
        if let swatch = SlotColor.swatches.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame }) { return swatch.color }
        if let color = SlotColor(hex: raw) { return color }
        throw AgentError.usage("--color must be like #5B9BFF, a swatch (" + SlotColor.swatches.map { $0.name.lowercased() }
                               .joined(separator: ", ") + "), or app")
    }

    /// "front", or an app by bundle id or name.
    private static func sendTarget(_ raw: String) throws -> SendTarget {
        if ["front", "frontmost"].contains(raw.lowercased()) { return .frontmost }
        let workspace = NSWorkspace.shared
        var url = workspace.urlForApplication(withBundleIdentifier: raw)
        if url == nil {
            url = workspace.runningApplications.first { $0.localizedName?.caseInsensitiveCompare(raw) == .orderedSame }?.bundleURL
        }
        if url == nil {
            for folder in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
                let candidate = URL(fileURLWithPath: folder).appending(path: raw.hasSuffix(".app") ? raw : raw + ".app")
                if FileManager.default.fileExists(atPath: candidate.path) { url = candidate; break }
            }
        }
        guard let url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            throw AgentError.notFound("no app called \"\(raw)\". Give its name as in /Applications, or its bundle id")
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return .app(bundleID: id, name: name)
    }
}
