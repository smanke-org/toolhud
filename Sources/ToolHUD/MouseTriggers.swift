import AppKit
import ToolHUDKit

/// Opens the HUD from the mouse in any app: hold right-click, ⌥ + right-click, the middle
/// button or a side button.
///
/// No app can add items to every other app's right-click menu, so this watches the button
/// itself through an event tap and keeps the trigger's clicks from reaching the app under
/// the pointer. For "Hold right-click", the press is held back until it's clear what it is:
/// let go quickly (or start dragging) and ToolHUD replays it, so the app's own menu still
/// opens; hold it and the HUD opens instead.
///
/// The tap needs Accessibility; it's set up again whenever trust or the setting changes.
@MainActor
final class MouseTriggers {
    static let shared = MouseTriggers()

    var onOpen: (() -> Void)?
    /// The trigger button came up after opening the HUD.
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private enum State {
        case idle
        /// Hold right-click: the press is held back while the timer runs.
        case waiting(down: CGEvent, start: CGPoint, timer: Timer)
        /// The HUD is open from this button; its drags and release are kept from the app.
        case open
        /// A held-back press turned out to be an ordinary right-drag; let the rest through.
        case passing
    }
    private var state = State.idle

    func apply() {
        stop()
        let trigger = Preferences.shared.mouseTrigger
        guard trigger != .none else { return }
        guard AccessibilityTrust.shared.isTrusted else {
            NSLog("ToolHUD: the mouse trigger waits for Accessibility access")
            return
        }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: mouseTapCallback, userInfo: nil) else {
            NSLog("ToolHUD: couldn't create the mouse event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if case .waiting(_, _, let timer) = state { timer.invalidate() }
        state = .idle
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// macOS turns a tap off if it's ever slow to answer; turn it straight back on.
    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Whether the event should go on to the app under the pointer.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let trigger = Preferences.shared.mouseTrigger
        guard let wanted = trigger.buttonNumber,
              Int(event.getIntegerValueField(.mouseEventButtonNumber)) == wanted else { return true }
        let isDown = type == .rightMouseDown || type == .otherMouseDown
        let isUp = type == .rightMouseUp || type == .otherMouseUp

        switch state {
        case .idle:
            guard isDown else { return true }
            switch trigger {
            case .holdRight:
                guard let copy = event.copy() else { return true }
                let timer = Timer.scheduledTimer(withTimeInterval: Preferences.shared.holdDelay, repeats: false) { _ in
                    MainActor.assumeIsolated { MouseTriggers.shared.holdElapsed() }
                }
                state = .waiting(down: copy, start: event.location, timer: timer)
                return false
            case .optionRight:
                guard event.flags.contains(.maskAlternate) else { return true }
                state = .open
                onOpen?()
                return false
            default:
                state = .open
                onOpen?()
                return false
            }

        case .waiting(let down, let start, let timer):
            if isUp {
                // A quick click: give the app its right-click after all.
                timer.invalidate()
                state = .idle
                replay([down, event])
                return false
            }
            let moved = hypot(event.location.x - start.x, event.location.y - start.y)
            if !isDown, moved > 6 {
                // A right-drag: replay the press and let the drag carry on.
                timer.invalidate()
                state = .passing
                replay([down])
                return true
            }
            return false

        case .open:
            if isUp {
                state = .idle
                onRelease?()
            }
            return false

        case .passing:
            if isUp { state = .idle }
            return true
        }
    }

    private func holdElapsed() {
        guard case .waiting = state else { return }
        state = .open
        onOpen?()
    }

    /// Posts copies of held-back events, marked so this tap lets them through.
    private func replay(_ events: [CGEvent]) {
        for original in events {
            guard let copy = original.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: ActionRunner.eventMarker)
            copy.post(tap: .cgSessionEventTap)
        }
    }
}

private func mouseTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { MouseTriggers.shared.reenable() }
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == ActionRunner.eventMarker {
        return Unmanaged.passUnretained(event)
    }
    // The tap's run loop source is on the main run loop, so the event never leaves this
    // thread; CGEvent just isn't Sendable.
    nonisolated(unsafe) let mainEvent = event
    let pass = MainActor.assumeIsolated { MouseTriggers.shared.handle(type, mainEvent) }
    return pass ? Unmanaged.passUnretained(event) : nil
}
