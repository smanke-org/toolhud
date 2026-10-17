import AppKit
import ApplicationServices
import Observation
import ToolHUDKit

/// Accessibility trust, which keystroke buttons and the mouse triggers need.
///
/// macOS sends no notification when it changes, so it's polled; the mouse triggers are set
/// up again when it does, because an event tap made before trust was granted never starts
/// receiving events.
@Observable
@MainActor
final class AccessibilityTrust {
    static let shared = AccessibilityTrust()

    private(set) var isTrusted = AXIsProcessTrusted()
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AccessibilityTrust.shared.check() }
        }
    }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func check() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        NSLog("ToolHUD: Accessibility trust is now \(trusted)")
        onChange?()
    }
}

/// Runs a button.
@MainActor
enum ActionRunner {
    /// Marks keystrokes ToolHUD posts, so its own event tap lets them through.
    nonisolated static let eventMarker: Int64 = 0x544F_4F4C // "TOOL"

    static func run(_ slot: Slot) {
        switch slot.mode {
        case .lens: runLens(slot)
        case .keystroke: runKeystroke(slot)
        }
    }

    // MARK: - Lens actions

    private static func runLens(_ slot: Slot) {
        let directory = LensDirectory.shared
        guard let id = slot.lensApp, let app = directory.app(id), let featureID = slot.lensFeature,
              let feature = app.feature(featureID) else {
            Toast.show("\(slot.name) has no action yet. Set one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        // Looked up again: the app may have been installed or updated since launch.
        if directory.installed[id] == nil { directory.refresh() }
        guard let installed = directory.installed[id] else {
            Toast.show("\(app.name) isn't installed.", symbol: "questionmark.app")
            return
        }

        if installed.supportsURLs, let url = app.url(for: featureID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = feature.activates
            NSWorkspace.shared.open([url], withApplicationAt: installed.url, configuration: configuration) { _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Toast.show("\(app.name) didn't respond: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
                    }
                }
            }
        } else if LensCatalog.isOpenOnly(featureID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: installed.url, configuration: configuration)
        } else if let shortcut = feature.shortcut {
            // An older version without lens actions: its own shortcut does the same thing,
            // as long as it hasn't been changed there.
            post(shortcut)
        } else {
            Toast.show("Update \(app.name) to use \(feature.title) from ToolHUD.", symbol: "arrow.down.app")
        }
    }

    // MARK: - Keystrokes

    private static func runKeystroke(_ slot: Slot) {
        guard let keys = slot.keySequence, !keys.keys.isEmpty else {
            Toast.show("\(slot.name) has no keystroke yet. Set one in ToolHUD Settings › Buttons.", symbol: "exclamationmark.triangle")
            return
        }
        switch slot.sendTo {
        case .frontmost:
            post(keys)
        case .app(let bundleID, let name):
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                running.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    MainActor.assumeIsolated { post(keys) }
                }
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        MainActor.assumeIsolated {
                            if let error {
                                Toast.show("\(name) didn't open: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
                            } else {
                                post(keys)
                            }
                        }
                    }
                }
            } else {
                Toast.show("\(name) isn't installed.", symbol: "questionmark.app")
            }
        }
    }

    static func post(_ shortcut: Shortcut) { post(KeySequence(shortcut)) }

    /// Presses the keys in turn, each with the sequence's modifiers held, as if typed.
    /// Needs Accessibility: without it macOS drops the events silently, so ask rather than
    /// appear to do nothing.
    static func post(_ sequence: KeySequence) {
        guard AccessibilityTrust.shared.isTrusted else {
            AccessibilityTrust.shared.request()
            Toast.show("ToolHUD needs Accessibility access to press keys. Turn it on in System Settings › Privacy & Security.",
                       symbol: "hand.raised")
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for (i, press) in sequence.keys.enumerated() {
            var modifiers = sequence.modifiers
            if press.shift { modifiers.insert(.shift) }
            let flags = Shortcut(keyCode: press.keyCode, modifiers: modifiers, key: press.key).cgFlags
            // A short gap between keys, so apps that read a chord (⌘K, then ⌘S) see two presses.
            if i > 0 { usleep(15_000) }
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(press.keyCode), keyDown: keyDown) else { continue }
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
                // The HID level, so other apps' global shortcuts (our lens apps' included) see it.
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

/// A short note in the middle of the screen with the pointer, which clicks pass through.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, symbol: String) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.preferredMaxLayoutWidth = 380
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        icon.contentTintColor = .white
        let stack = NSStackView(views: [icon, label])
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 18)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.cornerCurve = .continuous
        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        let size = stack.fittingSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 120,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    Toast.panel?.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { Toast.panel?.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}
