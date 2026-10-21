import AppKit

/// ToolHUD's side of the menu hub: our other apps' menus as submenus of ToolHUD's menu bar
/// item, while those apps hide their own icons (see `MenuHub` for the app side).
///
/// ToolHUD's port is the signal the apps watch for. It is open only while the hub is on and
/// ToolHUD's own icon shows, so an app never hides into a menu that isn't there.
@MainActor
final class MenuHubHost: NSObject, NSMenuDelegate {
    static let shared = MenuHubHost()
    static let key = "gatherAppMenus"

    /// On by default; synced.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            guard newValue != isEnabled || UserDefaults.standard.object(forKey: key) == nil else { return }
            UserDefaults.standard.set(newValue, forKey: key)
            SettingsSync.shared.localDidChange()
            shared.apply()
        }
    }

    /// A submenu that knows whose menu it holds.
    private final class GuestMenu: NSMenu {
        var bundleID = ""
    }

    private struct Pick {
        var bundleID: String
        var path: String
    }

    /// A run loop mode of our own for waiting on replies, so nothing else runs meanwhile.
    private static let replyMode = "com.smanke.ToolHUD.menuHub" as CFString
    private var port: CFMessagePort?

    /// Opens or closes ToolHUD's port to match the setting and the menu bar icon, and tells
    /// the apps either way.
    func apply() {
        let wanted = Self.isEnabled && AppPresence.showInMenuBar
        if wanted, port == nil {
            var context = CFMessagePortContext()
            var shouldFree: DarwinBoolean = false
            guard let local = CFMessagePortCreateLocal(nil, MenuHub.hostPortName as CFString, { _, id, data, _ in
                let bundleID = data.flatMap { String(data: $0 as Data, encoding: .utf8) }
                MainActor.assumeIsolated {
                    if id == MenuHub.Message.activate.rawValue, let bundleID { MenuHubHost.shared.bringForward(bundleID) }
                }
                return nil
            }, &context, &shouldFree) else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMessagePortCreateRunLoopSource(nil, local, 0), .commonModes)
            port = local
        } else if !wanted, let port {
            CFMessagePortInvalidate(port)
            self.port = nil
        } else {
            return
        }
        Self.announce()
    }

    /// Closes the port on the way out, so the icons come back at once rather than when the
    /// apps notice ToolHUD has gone.
    func stop() {
        guard let port else { return }
        CFMessagePortInvalidate(port)
        self.port = nil
        Self.announce()
    }

    private static func announce() {
        DistributedNotificationCenter.default().postNotificationName(MenuHub.changed, object: nil, userInfo: nil,
                                                                     deliverImmediately: true)
    }

    /// The running apps that have handed their menu to ToolHUD, by name.
    func guests() -> [NSRunningApplication] {
        guard port != nil else { return [] }
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard let id = app.bundleIdentifier, id.hasPrefix("com.smanke."), id != Bundle.main.bundleIdentifier else { return false }
                return MenuHub.portExists(MenuHub.appPortName(id))
            }
            .sorted { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
    }

    /// The app's short name: M3 Tracker's display name is its long, descriptive one.
    static func name(of app: NSRunningApplication) -> String {
        app.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
            ?? app.localizedName ?? app.bundleIdentifier ?? ""
    }

    /// One row per guest app, each with its menu as a submenu filled when it opens.
    func addItems(to menu: NSMenu) {
        let apps = guests()
        guard !apps.isEmpty else { return }
        menu.addItem(.separator())
        for app in apps {
            guard let id = app.bundleIdentifier else { continue }
            let name = Self.name(of: app)
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            // The app's live menu bar icon, so its state still shows; else its app icon.
            item.image = send(.icon, to: id).flatMap { try? JSONDecoder().decode(HubImage.self, from: $0) }?.image
                ?? Self.smallIcon(app.icon)
            let submenu = GuestMenu(title: name)
            submenu.bundleID = id
            submenu.autoenablesItems = false
            submenu.delegate = self
            item.submenu = submenu
            menu.addItem(item)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let guest = menu as? GuestMenu else { return }
        menu.removeAllItems()
        if let data = send(.menu, to: guest.bundleID), let items = try? JSONDecoder().decode([HubItem].self, from: data) {
            fill(menu, with: items, bundleID: guest.bundleID)
        } else {
            // The app didn't answer in time (busy or hung): offer to bring it up instead.
            let open = NSMenuItem(title: "Open \(guest.title)", action: #selector(openApp(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = guest.bundleID
            menu.addItem(open)
        }
    }

    private func fill(_ menu: NSMenu, with items: [HubItem], bundleID: String) {
        for entry in items {
            if entry.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: entry.children == nil ? #selector(pick(_:)) : nil,
                                  keyEquivalent: entry.key)
            item.target = self
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: entry.modifiers)
            item.state = NSControl.StateValue(rawValue: entry.state)
            item.isEnabled = entry.isEnabled
            item.isAlternate = entry.isAlternate
            item.indentationLevel = entry.indentation
            item.toolTip = entry.toolTip
            item.image = entry.image?.image
            item.representedObject = Pick(bundleID: bundleID, path: entry.path)
            if let children = entry.children {
                let submenu = NSMenu(title: entry.title)
                submenu.autoenablesItems = false
                fill(submenu, with: children, bundleID: bundleID)
                item.submenu = submenu
            }
            menu.addItem(item)
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let pick = sender.representedObject as? Pick else { return }
        // The click happened here; let the app come forward if what it runs opens a window.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: pick.bundleID).first {
            NSApp.yieldActivation(to: app)
        }
        _ = send(.invoke, to: pick.bundleID, data: Data(pick.path.utf8), awaitReply: false)
    }

    /// An app opened a window from one of its items here. ToolHUD had the click, so it may
    /// activate, and an active app may hand activation on.
    fileprivate func bringForward(_ bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        NSLog("ToolHUD: menu hub bringing \(bundleID) forward")
        NSApp.activate()
        NSApp.yieldActivation(to: app)
        app.activate(from: .current, options: [])
    }

    @objc private func openApp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Asks an app's port, waiting half a second at most for the answer.
    private func send(_ message: MenuHub.Message, to bundleID: String, data: Data = Data(), awaitReply: Bool = true) -> Data? {
        guard let remote = CFMessagePortCreateRemote(nil, MenuHub.appPortName(bundleID) as CFString) else { return nil }
        defer { CFMessagePortInvalidate(remote) }
        var reply: Unmanaged<CFData>?
        let status = awaitReply
            ? CFMessagePortSendRequest(remote, message.rawValue, data as CFData, 0.5, 0.5, Self.replyMode, &reply)
            : CFMessagePortSendRequest(remote, message.rawValue, data as CFData, 0.5, 0, nil, nil)
        guard status == kCFMessagePortSuccess, let reply else { return nil }
        return reply.takeRetainedValue() as Data
    }

    private static func smallIcon(_ icon: NSImage?) -> NSImage? {
        guard let icon = icon?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
