#if DEBUG
import AppKit

/// Debug builds only. `TOOLHUD_DEBUG_UPDATE_NOTES=<folder>`: fetches the notes of ToolHUD's
/// own releases, draws the update prompt, the What's New sheet Settings shows after an
/// automatic update, and Settings itself to PNGs, writes report.txt, and quits. It's a
/// staging run, so it starts nothing else (no HUD, triggers, sync or updater), but What's New
/// keeps its record in the app's defaults: run it from a copy with its own bundle identifier.
@MainActor
enum DebugUpdateNotes {
    static func run(folder: String) {
        guard Bundle.main.bundleIdentifier != "com.smanke.ToolHUD" else {
            NSLog("ToolHUD: run this test from a copy with its own bundle identifier")
            exit(2)
        }
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var report: [String] = []
        func note(_ line: String) {
            report.append(line)
            try? report.joined(separator: "\n").appending("\n").write(to: out.appending(path: "report.txt"), atomically: true, encoding: .utf8)
        }
        func contentSize() -> CGSize {
            SettingsWindow.shared.debugWindow.map { $0.contentRect(forFrameRect: $0.frame).size } ?? .zero
        }

        Task {
            note("running \(AppInfo.version) as \(Bundle.main.bundleIdentifier ?? "?")")
            // The update prompt, as someone on 1.1.12 would see it offered 2.0.1.
            let notes = await ReleaseNotes.fetch(newAfter: "1.1.12", through: "2.0.1")
            note("notes fetched: \(notes.map { $0.version + ($0.isNew ? " new" : "") })")
            let alert = UpdateController.makeConfirmAlert(newVersion: "2.0.1", current: "1.1.12", notes: notes)
            alert.layout()
            alert.window.orderFront(nil)
            try? await Task.sleep(for: .seconds(1))
            render(alert.window, to: out.appending(path: "update-prompt.png"))
            note("buttons: \(alert.buttons.map { "\($0.title) key='\($0.keyEquivalent)'" })")
            note("reminder box: '\(alert.suppressionButton?.title ?? "none")' on by default: \(alert.suppressionButton?.state == .on)")
            alert.window.orderOut(nil)

            // A brand-new install shows nothing.
            WhatsNew.shared.noteLaunch(newInstall: true, autoInstalledFrom: nil)
            note("new install pending: \(String(describing: WhatsNew.shared.pending))")
            // What's New in Settings after an automatic update from the release before this one.
            let previous = notes.first { UpdateController.isNewer(AppInfo.version, than: $0.version) }?.version ?? "2.0.0"
            WhatsNew.shared.noteLaunch(newInstall: false, autoInstalledFrom: previous)
            note("auto-update from \(previous) pending: \(String(describing: WhatsNew.shared.pending))")
            // Appearance, not General: General hangs SwiftUI layout in a staging run (sync never started).
            SettingsWindow.shared.show(.appearance)
            try? await Task.sleep(for: .seconds(4))
            render(SettingsWindow.shared.debugWindow?.attachedSheet, to: out.appending(path: "whats-new.png"))
            note("sheet shown: \(SettingsWindow.shared.debugWindow?.attachedSheet != nil)")
            if let window = SettingsWindow.shared.debugWindow, let sheet = window.attachedSheet { window.endSheet(sheet) }
            // OK with "Don't show this again" ticked puts it away for good.
            WhatsNew.shared.dismiss(forGood: true)
            note("after dismiss pending: \(String(describing: WhatsNew.shared.pending))")
            try? await Task.sleep(for: .seconds(1))
            render(SettingsWindow.shared.debugWindow, to: out.appending(path: "settings.png"))
            let window = SettingsWindow.shared.debugWindow
            note("settings resizable: \(window?.styleMask.contains(.resizable) == true) min \(window?.contentMinSize ?? .zero) content \(contentSize()) autosave '\(window?.frameAutosaveName ?? "")'")

            // Asked for from the What's New… button: this version's notes, no "Don't show" box.
            SettingsWindow.shared.showWhatsNew()
            try? await Task.sleep(for: .seconds(3))
            render(SettingsWindow.shared.debugWindow?.attachedSheet, to: out.appending(path: "whats-new-asked.png"))
            note("asked sheet shown: \(SettingsWindow.shared.debugWindow?.attachedSheet != nil)")
            if let window = SettingsWindow.shared.debugWindow, let sheet = window.attachedSheet { window.endSheet(sheet) }

            // Last, since it may hang here: the General pane with the What's New… button.
            note("opening General")
            SettingsWindow.shared.show(.general)
            try? await Task.sleep(for: .seconds(3))
            render(SettingsWindow.shared.debugWindow, to: out.appending(path: "general.png"))
            // Scrolled down to Updates, where What's New… sits beside Check Now.
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let form = SettingsWindow.shared.debugWindow?.contentView.map(scrollViews)?
                .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
            if let form, let document = form.documentView {
                let bottom = document.isFlipped ? document.frame.height - form.contentView.bounds.height : 0
                form.contentView.scroll(to: NSPoint(x: 0, y: max(bottom - 120, 0)))
                form.reflectScrolledClipView(form.contentView)
            }
            try? await Task.sleep(for: .seconds(1))
            render(SettingsWindow.shared.debugWindow, to: out.appending(path: "general-updates.png"))
            note("done")
            exit(0)
        }
    }

    private static func render(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
