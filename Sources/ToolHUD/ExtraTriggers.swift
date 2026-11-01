import AppKit
import ToolHUDKit

/// The other ways to open the HUD: double-tapping a modifier key, and resting the pointer
/// in a screen corner.
///
/// The double-tap listens through a listen-only event tap, which needs Accessibility like
/// the mouse triggers; it never holds back a key. The corner is checked a few times a
/// second from the pointer's position, which needs no permission.
@MainActor
final class ExtraTriggers {
    static let shared = ExtraTriggers()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector: DoubleTapDetector?
    private var cornerTimer: Timer?
    /// When the pointer arrived in the corner, and whether it has left since the HUD last
    /// opened from it.
    private var cornerSince: Date?
    private var cornerArmed = true

    func apply() {
        stop()
        let prefs = Preferences.shared
        if let key = prefs.doubleTapKey.modifier { startDoubleTap(key) }
        if prefs.hotCorner != .off {
            cornerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                MainActor.assumeIsolated { ExtraTriggers.shared.checkCorner() }
            }
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        detector = nil
        cornerTimer?.invalidate()
        cornerTimer = nil
        cornerSince = nil
        cornerArmed = true
    }

    // MARK: - Double-tap

    private func startDoubleTap(_ key: KeyModifiers) {
        guard AccessibilityTrust.shared.isTrusted else {
            NSLog("ToolHUD: double-tap waits for Accessibility access")
            return
        }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: extraTapCallback, userInfo: nil) else {
            NSLog("ToolHUD: couldn't create the double-tap event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        detector = DoubleTapDetector(key: key)
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        guard detector != nil else { return }
        guard type == .flagsChanged else {
            detector?.interrupt()
            return
        }
        // Keys ToolHUD presses for its buttons don't count.
        guard event.getIntegerValueField(.eventSourceUserData) != ActionRunner.eventMarker else { return }
        if detector?.flagsChanged(Self.modifiers(event.flags), at: ProcessInfo.processInfo.systemUptime) == true {
            HUDController.shared.toggle()
        }
    }

    private static func modifiers(_ flags: CGEventFlags) -> KeyModifiers {
        var held: KeyModifiers = []
        if flags.contains(.maskCommand) { held.insert(.command) }
        if flags.contains(.maskAlternate) { held.insert(.option) }
        if flags.contains(.maskControl) { held.insert(.control) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        return held
    }

    // MARK: - Screen corner

    private func checkCorner() {
        let corner = Preferences.shared.hotCorner
        let mouse = NSEvent.mouseLocation
        // Not while dragging: a window or a selection pushed into the corner isn't a request.
        let inCorner = NSEvent.pressedMouseButtons == 0 && NSScreen.screens.contains { screen in
            let f = screen.frame
            return corner.contains(x: mouse.x, y: mouse.y, minX: f.minX, minY: f.minY, maxX: f.maxX, maxY: f.maxY)
        }
        guard inCorner else {
            cornerSince = nil
            cornerArmed = true
            return
        }
        guard cornerArmed, !HUDController.shared.isShowing else { return }
        let since = cornerSince ?? Date()
        cornerSince = since
        if Date().timeIntervalSince(since) >= Preferences.shared.cornerDelay {
            cornerArmed = false
            HUDController.shared.show()
        }
    }
}

private func extraTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    nonisolated(unsafe) let mainEvent = event
    MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            ExtraTriggers.shared.reenable()
        } else {
            ExtraTriggers.shared.handle(type, mainEvent)
        }
    }
    return Unmanaged.passUnretained(event)
}
