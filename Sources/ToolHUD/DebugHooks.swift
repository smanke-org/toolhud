#if DEBUG
import AppKit
import ToolHUDKit

/// Debug-only staging for the website's screenshots. A Debug build shares the installed
/// app's preferences, so these hooks only show things and never sync, update or save.
///
///   TOOLHUD_DEBUG_HUD=halo:0           opens that look with button 0 lit
///   TOOLHUD_DEBUG_SETTINGS=appearance  opens that Settings pane
///
/// Both open on the first Retina display, so the shots are taken at 2×.
@MainActor
enum DebugHooks {
    static var freezeHighlight = false

    static func trace(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_TRACE"] else { return }
        try? (s + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    static var screen: NSScreen? {
        NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? NSScreen.main
    }

    /// Starts a staging run if one was asked for; returns whether it did.
    static func run() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if let spec = env["TOOLHUD_DEBUG_HUD"] {
            let parts = spec.split(separator: ":")
            guard let look = parts.first.flatMap({ Visualization(rawValue: String($0)) }) else { return false }
            let index = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { HUDController.shared.debugShow(look, highlight: index) }
            }
            return true
        }
        if let name = env["TOOLHUD_DEBUG_SETTINGS"], let pane = SettingsPane(rawValue: name) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    // Opened on Appearance first, as the app does, then switched.
                    SettingsWindow.shared.show(.appearance)
                    SettingsWindow.shared.show(pane)
                    if let window = SettingsWindow.shared.debugWindow,
                       let frame = screen?.visibleFrame {
                        window.setFrameAutosaveName("")
                        let size = NSSize(width: Double(env["TOOLHUD_DEBUG_WIDTH"] ?? "") ?? 960,
                                          height: Double(env["TOOLHUD_DEBUG_HEIGHT"] ?? "") ?? 760)
                        let target = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                            width: size.width, height: size.height)
                        window.setFrame(target, display: true)
                        // SwiftUI sizes the window again once the pane has laid out.
                        window.isRestorable = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            MainActor.assumeIsolated {
                                // The window server ignores moves of a window already on screen.
                                window.orderOut(nil)
                                window.setFrame(target, display: true)
                                window.makeKeyAndOrderFront(nil)
                                trace("moved to \(window.frame) number=\(window.windowNumber) visible=\(window.isVisible) screen=\(String(describing: window.screen?.localizedName))")
                            }
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}
#endif
