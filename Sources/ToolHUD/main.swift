import AppKit
import SwiftUI
import ToolHUDKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(AppPresence.showInDock ? .regular : .accessory)
app.run()

/// Launch, the menu bar item, the Dock menu, and reopening.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = AppPresence.mainMenu(appName: AppInfo.name, settingsTitle: "Settings…",
                                            target: self, settings: #selector(showSettings))
        // Right below About in the app menu.
        mainMenu.items.first?.submenu?.insertItem(item("Our other apps…", #selector(showOtherApps)), at: 1)
        NSApp.mainMenu = mainMenu

        // Set at the end of the first launch, so its absence means a brand-new install.
        let newInstall = !UserDefaults.standard.bool(forKey: "askedForAccessibility")
        #if DEBUG
        // Screenshot runs share the installed app's settings, so they stage and stop there.
        if DebugHooks.run() { return }
        #endif
        if newInstall { SettingsSync.shared.adoptOnNewInstall() }
        SettingsSync.shared.start()

        HUDController.shared.start()
        HotKeyCenter.shared.apply()
        AccessibilityTrust.shared.onChange = { MouseTriggers.shared.apply() }
        AccessibilityTrust.shared.start()
        MouseTriggers.shared.apply()

        setUpStatusItem()
        NotificationCenter.default.addObserver(forName: AppPresence.menuBarDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.statusItem?.isVisible = AppPresence.showInMenuBar }
        }
        // An app installed or updated while ToolHUD runs shows up the next time it's needed.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LensDirectory.shared.refresh() }
        }

        // The mouse triggers and keystroke buttons need Accessibility; ask once on first
        // launch so they work the first time they're used.
        if newInstall {
            UserDefaults.standard.set(true, forKey: "askedForAccessibility")
            if !AccessibilityTrust.shared.isTrusted { AccessibilityTrust.shared.request() }
        }

        AutoUpdater.shared.start()
        if newInstall || (!AppPresence.showInMenuBar && !AppPresence.showInDock) { showSettings() }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = AppPresence.dockMenu(title: "Settings…", target: self, action: #selector(showSettings))
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(item("Show HUD", #selector(showHUD)), at: 0)
        return menu
    }

    /// Opening the app again (from Applications, Spotlight, or the Dock tile) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// `toolhud://show` opens the HUD and `toolhud://settings` opens Settings, for Shortcuts,
    /// scripts and our other apps.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "toolhud" {
            switch url.host {
            case "show": showHUD()
            default: showSettings()
            }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = AppPresence.showInMenuBar
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let show = item("Show HUD", #selector(showHUD))
        if let shortcut = Preferences.shared.hotKey?.menuKeyEquivalent {
            show.keyEquivalent = shortcut.key
            show.keyEquivalentModifierMask = shortcut.mask
        }
        menu.addItem(show)

        if !AccessibilityTrust.shared.isTrusted {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "Allow Mouse Triggers and Keystrokes…", action: #selector(allowAccessibility), keyEquivalent: "")
            warn.target = self
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        if let staged = AutoUpdater.shared.staged {
            menu.addItem(item("Update to \(staged.version) Now (Otherwise Installs When Idle)", #selector(installUpdateNow)))
        } else if let pending = UpdateAvailability.shared.pending {
            menu.addItem(item("Update to \(pending)…", #selector(checkForUpdates)))
        } else {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        }
        menu.addItem(item("About \(AppInfo.name)", #selector(showAbout)))
        menu.addItem(item("Our other apps…", #selector(showOtherApps)))
        menu.addItem(.separator())
        let version = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.displayVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(item("Quit \(AppInfo.name)", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    /// From a menu the pointer is up at the menu bar, so the HUD opens mid-screen instead.
    @objc func showHUD() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { HUDController.shared.show(atScreenCenter: true) }
        }
    }
    @objc func showSettings() { SettingsWindow.shared.show() }
    @objc func checkForUpdates() { UpdateController.checkForUpdates() }
    @objc func installUpdateNow() { AutoUpdater.shared.installNow() }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func allowAccessibility() {
        AccessibilityTrust.shared.request()
        AccessibilityTrust.shared.openSettings()
    }

    /// The developer's site, which lists every app.
    @objc func showOtherApps() {
        if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
    }
    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
