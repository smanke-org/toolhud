import AppKit
import SwiftUI
import ToolHUDKit

// MARK: - Content

/// One page of Help. `{shortcut}` shows the user's HUD shortcut and `{mouse}` their mouse
/// trigger, so the text matches their own settings.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum HelpBlock {
    case text(String)
    case heading(String)
    /// Keys on the left, what they do on the right.
    case keys([(String, String)])
    case tip(String)

    var searchText: String {
        switch self {
        case .text(let s), .heading(let s), .tip(let s): Help.resolve(s)
        case .keys(let rows): rows.map { Help.resolve($0.0) + " " + Help.resolve($0.1) }.joined(separator: " ")
        }
    }
}

@MainActor
enum Help {
    static func resolve(_ text: String) -> String {
        guard text.contains("{") else { return text }
        let prefs = Preferences.shared
        return text
            .replacingOccurrences(of: "{shortcut}", with: prefs.hotKey?.display ?? "(no shortcut set)")
            .replacingOccurrences(of: "{mouse}", with: prefs.mouseTrigger == .none ? "(no mouse trigger set)" : prefs.mouseTrigger.title)
    }

    /// The topic each Settings pane's Help button opens.
    static func topic(for pane: SettingsPane) -> String {
        switch pane {
        case .general: "getting-started"
        case .appearance: "looks"
        case .buttons: "buttons"
        case .features: "features"
        case .triggers: "opening"
        case .activity: "activity"
        }
    }

    static var topics: [HelpTopic] { [
        HelpTopic(id: "getting-started", title: "Getting Started", symbol: "sparkles", blocks: [
            .text("ToolHUD opens a ring of buttons around the pointer. Each button runs a feature from one of your apps, such as capturing text with TextLens or opening Quick Paste in PasteLens, or presses keys for you. Click a button, or press its number."),
            .heading("Open the HUD"),
            .keys([
                ("{shortcut}", "Your keyboard shortcut"),
                ("{mouse}", "Your mouse trigger"),
                ("Menu bar icon", "Show HUD, Settings and updates"),
            ]),
            .text("Change both in Settings › Triggers. The HUD stays open until you click a button, press Esc, or press the shortcut again."),
            .heading("Allow Accessibility"),
            .text("Mouse triggers and keystroke buttons need Accessibility permission (macOS 27 calls it Device Control). App features and the keyboard shortcut work without it. If the menu bar menu shows \"Allow Mouse Triggers and Keystrokes…\", choose it."),
            .tip("Settings › Appearance › Try it › Show HUD opens the HUD in the middle of the screen, to see a new look or button."),
        ]),

        HelpTopic(id: "using", title: "Using the HUD", symbol: "circle.circle", blocks: [
            .text("Each button shows a small keycap with its number. Buttons run when you click them or pick them with the keyboard. Letting go of the shortcut or the mouse button does nothing, so you can take your time."),
            .keys([
                ("1 – 9", "Run button 1 to 9"),
                ("0", "Run button 10"),
                ("A S D F G H J K", "Run the button pad, first to last"),
                ("← → ↑ ↓", "Light the next or previous button"),
                ("Tab / ⇧Tab", "Light the next or previous button"),
                ("Scroll", "Light the next or previous button (and turn the Dial look)"),
                ("Return or Space", "Run the lit button"),
                ("/", "Search buttons, app features, app menus and shortcuts (when Type to search is on)"),
                ("Space with nothing lit", "Run the last action again (when that's turned on)"),
                (",", "Open Settings"),
                ("Esc", "Close the HUD, or go back out of a folder or the search"),
                ("{shortcut} again", "Close the HUD"),
                ("Gear button", "Open Settings"),
            ]),
            .text("The middle of the HUD names the button you're pointing at, the app it belongs to and what it does."),
            .tip("Buttons 11 and 12 have no number key; click them or light them with the arrow keys. A number with no button beeps."),
        ]),

        HelpTopic(id: "buttons", title: "Buttons", symbol: "square.grid.2x2", blocks: [
            .text("Settings › Buttons lists the ring's buttons in order; button 1 sits at the top and the rest follow clockwise. Drag to reorder, and use + and − to set how many there are, from 2 to 12. Fewer buttons are faster to aim at. Right-click a button to test, duplicate or delete it (Delete asks first); the Delete key also deletes the selected button."),
            .heading("What a button can do"),
            .text("Choose under When chosen:"),
            .keys([
                ("Lens action", "Run a feature of TextLens, ClickLens, PasteLens, DiskLens, ExpansionLens, CaptureLens or another supported app"),
                ("Keystroke", "Press keys for you, in the app you were using or one you choose"),
                ("Shortcut", "Run a shortcut from the Shortcuts app"),
                ("Open", "Open a web page, or a file, folder or app"),
                ("Type text", "Type or paste a piece of text; pasting puts your clipboard back afterwards"),
                ("Menu item", "Choose a menu item, such as File > Export…, in the app you were using or one you pick. Choose… reads a running app's menus for you"),
                ("Script", "Run an AppleScript or a shell command in the background"),
                ("Steps", "Run several of these in turn, with a wait after each"),
                ("Folder", "Open a smaller ring of more buttons (when folders are on)"),
                ("App menu", "Show one of our apps' menus at the pointer (when app menu buttons are on)"),
            ]),
            .heading("Steps"),
            .text("A Steps button holds up to 12 steps. Edit… sets what each one does, and Then wait gives an app time to catch up before the next step. The ⋯ menu moves, duplicates or removes a step."),
            .heading("Keystroke buttons"),
            .text("Turn on ⌘ ⌥ ⌃ ⇧ with the toggles, then type the keys: K means the K key. Type several keys to press them one after another. Special Keys adds keys you can't type, such as arrows, Return or [F5]. \"Send to\" picks the app that receives them."),
            .heading("Looks and sharing"),
            .text("Each button has an SF Symbol icon (Choose… to browse) and a color; App color uses the app's own. Test This Button runs it without opening the HUD. Export Ring… saves your buttons, button pad and look to a ring file to keep or share; Import Ring… loads one."),
            .heading("The button pad"),
            .text("With the button pad on, a Ring / Pad switch sits above the list. Pad holds the pad's own buttons, from 1 to 8, which run on A, S, D, F, G, H, J and K."),
        ]),

        HelpTopic(id: "features", title: "Features", symbol: "switch.2", blocks: [
            .text("Settings › Features turns on extras for people who like to customize. Only Type to search starts on; the rest wait until you want them, and turning one off keeps the buttons you've made."),
            .heading("Type to search"),
            .text("With the HUD open, press / and type. The search finds your buttons (every app's ring and folder included), every feature of your installed apps, items in the menus gathered in ToolHUD's menu, and shortcuts from the Shortcuts app. ↑ ↓ choose, Return runs, Delete on an empty search or Esc goes back to the buttons."),
            .heading("Run the last action again"),
            .text("Point at the middle of the HUD to see what ran last, then click, or press Space with no button lit. Shortcuts and scripts can open toolhud://repeat."),
            .heading("Folder buttons"),
            .text("Choose Folder under When chosen, then Edit Folder… to fill it with up to 12 buttons. In the HUD, the folder's buttons take the ring's place; Esc or Delete comes back out."),
            .heading("A different ring for each app"),
            .text("At the top of Buttons, + adds an app, starting from a copy of your usual buttons. While that app is in front, the HUD shows its ring (and its pad); everywhere else, the usual one. The menu above the list switches which ring you're editing, and − removes an app's ring."),
            .heading("App menu buttons"),
            .text("An App menu button shows one of our apps' menus right at the pointer, the same menu as in ToolHUD's menu bar item. The app has to be running with its menu gathered into ToolHUD's."),
            .heading("Show which features are on"),
            .text("Buttons for features that switch on and off, such as ClickLens's spotlight, ExpansionLens, NetworkToggle's Wi-Fi or AudioLens's mute, get a small green light while they're on. Older versions of those apps don't report it, so their buttons show no light."),
        ]),

        HelpTopic(id: "apps", title: "Supported Apps", symbol: "app.badge", blocks: [
            .text("App feature buttons ask another app to do something through its own link (a URL scheme), so the app must be installed. A button for a missing app shows a link to download it."),
            .keys([
                ("TextLens", "Capture text, translate, read QR codes, history and more (1.0.11 or later)"),
                ("ClickLens", "Spotlight, click rings, boxes, arrows, keystrokes (1.5.6 or later)"),
                ("PasteLens", "Quick Paste, History, Stack, snippets"),
                ("DiskLens", "Scan a disk, open DiskLens (1.0.7 or later)"),
                ("ExpansionLens", "Quick search, new snippet, pause or resume"),
                ("CaptureLens", "Capture the screen, a window or an area, capture again, open the library"),
                ("AudioLens", "Turn the playing app up or down, mute it, switch outputs"),
                ("BatteryLens", "Show battery levels, refresh, devices"),
                ("M3 Tracker, NetworkToggle, StayMounted, WindowKeeper, DockMirror and others", "Their own actions, when installed in /Applications"),
            ]),
            .tip("Other apps can join by listing their actions in their Info.plist; ToolHUD finds them in /Applications."),
        ]),

        HelpTopic(id: "opening", title: "Opening the HUD", symbol: "cursorarrow.click.2", blocks: [
            .heading("Keyboard"),
            .text("Your shortcut is {shortcut}. Record a different one in Settings › Triggers; a warning appears if macOS or another app already uses it."),
            .heading("Mouse"),
            .text("Your mouse trigger is {mouse}. The HUD opens around the pointer in any app. Choices:"),
            .keys([
                ("Hold right-click", "Hold the right button; set how long with \"Hold for\". A quick right-click still opens menus"),
                ("⌥ + right-click", "Hold Option and right-click"),
                ("Middle button", "Click the wheel or middle button"),
                ("Side button (back or forward)", "The extra buttons on many mice"),
                ("None", "Keyboard only"),
            ]),
            .text("Mouse triggers need Accessibility permission. Settings › Appearance › Open at chooses whether the HUD opens at the pointer or the center of the screen."),
            .heading("More ways"),
            .keys([
                ("Double-tap", "Press ⌘, ⌥, ⌃ or ⇧ twice quickly on its own. Holding it for a shortcut never counts"),
                ("Screen corner", "Push the pointer into a corner and rest there; set how long with \"Rest for\""),
                ("Shortcuts app", "The Show ToolHUD action, with an app's ring or a folder by name, and Run ToolHUD's Last Action Again"),
                ("toolhud://show", "Open the HUD from a script; add ?ring=Safari for an app's ring or a folder"),
            ]),
        ]),

        HelpTopic(id: "looks", title: "Looks", symbol: "paintpalette", blocks: [
            .text("Settings › Appearance offers ten looks: Halo, Orbit, Dial, Stargate, Command Deck, Hive, Red Alert, Constellation, Glass Pills and Planetary. They all work the same way; only the drawing changes."),
            .keys([
                ("Opacity", "How see-through the HUD is"),
                ("Size", "Small, medium or large"),
                ("Open at", "The pointer or the center of the screen"),
                ("Sound / Haptic", "A soft sound when a button runs; a trackpad tap as you move between buttons"),
            ]),
            .heading("The button pad"),
            .text("For more buttons than the ring holds, turn on \"Add a button pad\" in Settings › Appearance. It adds up to 8 buttons beside the HUD, drawn to match the look: coins for the Halo, keycaps for the Command Deck, comb cells for the Hive, moons for Planetary, and so on. Put it in a column on the left or right, or in a row above or below. Its buttons run on A, S, D, F, G, H, J and K, and you choose what they do under Pad in Settings › Buttons."),
            .tip("The Dial look turns its bezel instead of lighting buttons: scroll or use the arrow keys to turn it."),
            .tip("Near a screen edge, the HUD moves inward so every button stays on screen."),
        ]),

        HelpTopic(id: "app-menus", title: "Your Apps' Menus", symbol: "menubar.rectangle", blocks: [
            .text("While ToolHUD runs, your other apps can leave the menu bar and live in ToolHUD's menu instead. Each one becomes a submenu under ToolHUD's icon, with the same items as its own menu, and its row shows the app's menu bar icon, so a warning badge still shows."),
            .text("Apps whose icon opens a panel, such as NetworkToggle, StayMounted and DiskLens, list their main actions there, plus a way to the full panel."),
            .text("Turn it on or off with \"Gather my other apps' menus here\" in Settings › General. Each app also has \"Put in ToolHUD's menu while ToolHUD is running\" in its own Settings, to keep just that one in the menu bar."),
            .tip("If ToolHUD quits, or its own menu bar icon is turned off, every app's icon comes back right away."),
        ]),

        HelpTopic(id: "activity", title: "Activity", symbol: "chart.bar.xaxis", blocks: [
            .text("Settings › Activity shows how many actions ToolHUD has run: a total for the period, a graph by day, week or month, and the total since ToolHUD started counting. Hover over a bar to see its count."),
            .text("Every button you run from the HUD or the button pad counts, whether you click it or press its key, and so does each item you pick from another app's menu in ToolHUD's menu. Test This Button in Settings doesn't count."),
            .text("The graph starts at 7 days and widens to 30, 90 and 180 days, then a year, as you keep using ToolHUD. Only the numbers are kept, never which buttons you ran."),
            .heading("All your Macs"),
            .text("With \"Sync settings with your other Macs\" on, each Mac shares its counts through iCloud Drive, encrypted like your settings. The This Mac / All Macs switch chooses which the graph shows, and the All Macs list shows each Mac's total and when it last synced. The switch is kept on each Mac."),
        ]),

        HelpTopic(id: "sync", title: "Sync and Settings", symbol: "icloud", blocks: [
            .text("Turn on \"Sync settings with your other Macs\" in Settings › General to share your buttons, look, shortcut, triggers and asking before quitting through iCloud Drive, and to add up Activity across your Macs. They're encrypted with a passphrase you choose; enter the same one on each Mac."),
            .text("Show in Dock and Show in menu bar choose where ToolHUD appears. With both off, open ToolHUD again from Finder or Spotlight to reach Settings."),
            .text("Reset to Defaults… puts buttons, look, shortcut, triggers and asking before quitting back to how ToolHUD started; login and sync stay as they are."),
            .tip("Quitting asks first, since the HUD's shortcut and mouse trigger stop and your apps' menus go back to their own icons. Turn off \"Ask before quitting\" in Settings › General, or tick \"Don't ask again\" when it asks."),
        ]),

        HelpTopic(id: "automation", title: "Automation", symbol: "gearshape.2", blocks: [
            .keys([
                ("toolhud://show", "Open the HUD"),
                ("toolhud://settings", "Open Settings"),
            ]),
            .text("Use these links from Shortcuts, scripts, or a launcher."),
        ]),

        HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
            .heading("The mouse trigger does nothing"),
            .text("ToolHUD needs Accessibility permission. Choose \"Allow Mouse Triggers and Keystrokes…\" in the menu bar menu, or switch ToolHUD on in System Settings › Privacy & Security. Also check that a trigger is chosen in Settings › Triggers."),
            .heading("A keystroke button types the wrong thing"),
            .text("Check \"Send to\": keys go to the app you were using unless you chose another. Some apps ignore synthetic keys in secure fields such as passwords."),
            .heading("An app button doesn't work"),
            .text("Make sure the app is installed and up to date (see Supported Apps). Open it once so macOS registers its link."),
            .heading("The shortcut does nothing"),
            .text("Another app may use the same keys. Record a different one in Settings › Triggers."),
        ]),
    ] }
}

// MARK: - Window

@Observable
@MainActor
final class HelpState {
    var selection: String? = "getting-started"
    var query = ""
}

@MainActor
final class HelpWindow: NSObject, NSWindowDelegate {
    static let shared = HelpWindow()

    let state = HelpState()
    private(set) var window: NSWindow?

    /// Opens Help, on `topic` when given.
    func show(topic: String? = nil) {
        if let topic { state.query = ""; state.selection = topic }
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(state: state))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppInfo.name) Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let screen = NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 820, height: min(600, screen - 80)))
            window.contentMinSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("ToolHUDHelp")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @Bindable var state: HelpState

    private var matches: [HelpTopic] {
        let query = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Help.topics }
        return Help.topics.filter { topic in
            topic.title.lowercased().contains(query) || topic.blocks.contains { $0.searchText.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(matches, selection: $state.selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .overlay {
                if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        } detail: {
            if let topic = Help.topics.first(where: { $0.id == state.selection }) {
                HelpPage(topic: topic, query: state.query)
            } else {
                Text("Choose a topic").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $state.query, placement: .sidebar, prompt: "Search Help")
        .onChange(of: state.query) {
            // Keep a matching topic on screen while searching.
            if let first = matches.first, !matches.contains(where: { $0.id == state.selection }) { state.selection = first.id }
        }
    }
}

struct HelpPage: View {
    let topic: HelpTopic
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: HelpBlock) -> some View {
        switch block {
        case .text(let s):
            Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(Help.resolve(s)).font(.title3.weight(.semibold)).padding(.top, 8)
        case .tip(let s):
            Label { Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .keys(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let keys = Help.resolve(row.0), what = Help.resolve(row.1)
                    let hit = !query.isEmpty && (keys + " " + what).lowercased().contains(query.lowercased())
                    GridRow {
                        Text(keys)
                            .font(.body.monospaced().weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            // The same key column width in every table on every page.
                            .frame(width: 210, alignment: .leading)
                        Text(what).fixedSize(horizontal: false, vertical: true)
                    }
                    .background(hit ? Color.yellow.opacity(0.25) : .clear)
                }
            }
        }
    }
}

/// The round "?" button macOS puts in the corner of settings panes.
struct HelpButton: NSViewRepresentable {
    let topic: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open))
        button.bezelStyle = .helpButton
        button.toolTip = "\(AppInfo.name) Help"
        button.setAccessibilityLabel("Help")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.topic = topic }

    func makeCoordinator() -> Coordinator { Coordinator(topic: topic) }

    @MainActor
    final class Coordinator: NSObject {
        var topic: String
        init(topic: String) { self.topic = topic }
        @objc func open() { HelpWindow.shared.show(topic: topic) }
    }
}
