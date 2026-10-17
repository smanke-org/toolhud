#if DEBUG
import AppKit
import ToolHUDKit

/// Debug-only staging for the website's screenshots. A Debug build shares the installed
/// app's preferences, so these hooks only show things and never sync, update or save.
///
///   TOOLHUD_DEBUG_HUD=halo:0           opens that look with button 0 lit
///                                      (TOOLHUD_DEBUG_DELAY=<seconds> waits first, so another app can come forward)
///   TOOLHUD_DEBUG_SETTINGS=appearance  opens that Settings pane
///   TOOLHUD_DEBUG_MISSING=<bundle id>    treats that lens app as not installed
///   TOOLHUD_DEBUG_BUTTON=<index>         starts Settings › Buttons on that button
///   TOOLHUD_DEBUG_POST_TEXT=ks TOOLHUD_DEBUG_POST_MODS=<raw> TOOLHUD_DEBUG_POST_ONLY_TO=<app name>
///                                      presses those keys, only if that app is in front
///
/// Both open on the first Retina display, so the shots are taken at 2×.
@MainActor
enum DebugHooks {
    static var freezeHighlight = false

    /// A lens app to treat as not installed, to see how Settings shows a missing app.
    static var missingApp: String? { ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_MISSING"] }

    /// The button Settings › Buttons starts on (0-based).
    static var selectedButton: Int? { ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_BUTTON"].flatMap { Int($0) } }

    static func trace(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["TOOLHUD_DEBUG_TRACE"] else { return }
        let line = Data((s + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: line)
        }
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
            let delay = Double(env["TOOLHUD_DEBUG_DELAY"] ?? "") ?? 1
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { HUDController.shared.debugShow(look, highlight: index) }
            }
            return true
        }
        if let text = env["TOOLHUD_DEBUG_POST_TEXT"], let target = env["TOOLHUD_DEBUG_POST_ONLY_TO"] {
            // Presses the keys, but only into the named app, so a stray run can't type into
            // whatever else is in front.
            let modifiers = KeyModifiers(rawValue: Int(env["TOOLHUD_DEBUG_POST_MODS"] ?? "") ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                MainActor.assumeIsolated {
                    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
                    guard front == target else { trace("not posted: \(front) is in front"); exit(2) }
                    let sequence = KeySequence.parse(text, modifiers: modifiers, lookup: KeyboardLayout.key(for:)).sequence
                    trace("posting \(sequence.display)")
                    ActionRunner.post(sequence)
                }
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
