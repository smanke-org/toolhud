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
        case .triggers: "opening"
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
                ("← → ↑ ↓", "Light the next or previous button"),
                ("Tab / ⇧Tab", "Light the next or previous button"),
                ("Scroll", "Light the next or previous button (and turn the Dial look)"),
                ("Return or Space", "Run the lit button"),
                (",", "Open Settings"),
                ("Esc", "Close the HUD"),
                ("{shortcut} again", "Close the HUD"),
                ("Gear button", "Open Settings"),
            ]),
            .text("The middle of the HUD names the button you're pointing at, the app it belongs to and what it does."),
            .tip("Buttons 11 and 12 have no number key; click them or light them with the arrow keys. A number with no button beeps."),
        ]),

        HelpTopic(id: "buttons", title: "Buttons", symbol: "square.grid.2x2", blocks: [
            .text("Settings › Buttons lists the ring's buttons in order; button 1 sits at the top and the rest follow clockwise. Drag to reorder, and use + and − to set how many there are, from 2 to 12. Fewer buttons are faster to aim at."),
            .heading("What a button can do"),
            .keys([
                ("App feature", "Run a feature of TextLens, ClickLens, PasteLens, DiskLens, ExpansionLens or another supported app"),
                ("Keystroke", "Press keys for you, in the app you were using or one you choose"),
            ]),
            .heading("Keystroke buttons"),
            .text("Turn on ⌘ ⌥ ⌃ ⇧ with the toggles, then type the keys: K means the K key. Type several keys to press them one after another. Special Keys adds keys you can't type, such as arrows, Return or [F5]. \"Send to\" picks the app that receives them."),
            .heading("Looks and sharing"),
            .text("Each button has an SF Symbol icon (Choose… to browse) and a color; App color uses the app's own. Test This Button runs it without opening the HUD. Export Ring… saves your buttons and look to a ring file to keep or share; Import Ring… loads one."),
        ]),

        HelpTopic(id: "apps", title: "Supported Apps", symbol: "app.badge", blocks: [
            .text("App feature buttons ask another app to do something through its own link (a URL scheme), so the app must be installed. A button for a missing app shows a link to download it."),
            .keys([
                ("TextLens", "Capture text, translate, read QR codes, history and more (1.0.11 or later)"),
                ("ClickLens", "Spotlight, click rings, boxes, arrows, keystrokes (1.5.6 or later)"),
                ("PasteLens", "Quick Paste, History, Stack, snippets"),
                ("DiskLens", "Scan a disk, open DiskLens (1.0.7 or later)"),
                ("ExpansionLens", "Quick search, new snippet, pause or resume"),
                ("M3 Tracker, NetworkToggle, StayMounted", "Their own actions, when installed in /Applications"),
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
        ]),

        HelpTopic(id: "looks", title: "Looks", symbol: "paintpalette", blocks: [
            .text("Settings › Appearance offers ten looks: Halo, Orbit, Dial, Stargate, Command Deck, Hive, Red Alert, Constellation, Glass Pills and Planetary. They all work the same way; only the drawing changes."),
            .keys([
                ("Opacity", "How see-through the HUD is"),
                ("Size", "Small, medium or large"),
                ("Open at", "The pointer or the center of the screen"),
                ("Sound / Haptic", "A soft sound when a button runs; a trackpad tap as you move between buttons"),
            ]),
            .tip("The Dial look turns its bezel instead of lighting buttons: scroll or use the arrow keys to turn it."),
            .tip("Near a screen edge, the HUD moves inward so every button stays on screen."),
        ]),

        HelpTopic(id: "app-menus", title: "Your Apps' Menus", symbol: "menubar.rectangle", blocks: [
            .text("While ToolHUD runs, your other apps can leave the menu bar and live in ToolHUD's menu instead. Each one becomes a submenu under ToolHUD's icon, with the same items as its own menu, and its row shows the app's menu bar icon, so a warning badge still shows."),
            .text("Apps whose icon opens a panel, such as NetworkToggle, StayMounted and DiskLens, list their main actions there, plus a way to the full panel."),
            .text("Turn it on or off with \"Gather my other apps' menus here\" in Settings › General. Each app also has \"Put in ToolHUD's menu while ToolHUD is running\" in its own Settings, to keep just that one in the menu bar."),
            .tip("If ToolHUD quits, or its own menu bar icon is turned off, every app's icon comes back right away."),
        ]),

        HelpTopic(id: "sync", title: "Sync and Settings", symbol: "icloud", blocks: [
            .text("Turn on \"Sync settings with your other Macs\" in Settings › General to share your buttons, look, shortcut and triggers through iCloud Drive. They're encrypted with a passphrase you choose; enter the same one on each Mac."),
            .text("Show in Dock and Show in menu bar choose where ToolHUD appears. With both off, open ToolHUD again from Finder or Spotlight to reach Settings."),
            .text("Reset to Defaults… puts buttons, look, shortcut and triggers back to how ToolHUD started; login and sync stay as they are."),
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
