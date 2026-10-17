import Foundation

/// The looks the HUD can take.
public enum Visualization: String, Codable, CaseIterable, Sendable, Identifiable {
    case halo, orbit, dial, stargate, commandDeck, hive, redAlert, constellation, glassPills, planetary

    public var id: String { rawValue }

    public enum Family: String, Sendable { case ring, hub }

    public var title: String {
        switch self {
        case .halo: "Halo"
        case .orbit: "Orbit"
        case .dial: "Dial"
        case .stargate: "Stargate"
        case .commandDeck: "Command Deck"
        case .hive: "Hive"
        case .redAlert: "Red Alert"
        case .constellation: "Constellation"
        case .glassPills: "Glass Pills"
        case .planetary: "Planetary"
        }
    }

    public var family: Family {
        switch self {
        case .commandDeck, .hive: .hub
        default: .ring
        }
    }

    public var blurb: String {
        switch self {
        case .halo: "Translucent slices; the one you point at lifts and glows."
        case .orbit: "Round buttons that spring out from the pointer."
        case .dial: "A rotary bezel that turns to what you point at, or as you scroll."
        case .stargate: "The chevrons are the buttons; the gate opens when one locks."
        case .commandDeck: "A panel of keycaps with app-colored lights."
        case .hive: "Honeycomb cells packed around a center hex."
        case .redAlert: "Crimson blades with hazard stripes on the armed one."
        case .constellation: "Star buttons joined by lines that draw themselves in."
        case .glassPills: "Labeled pills, the easiest to read at a glance."
        case .planetary: "Planets drift around a sun and stop the moment you aim."
        }
    }

    /// How the pointer picks a button.
    public var selection: HUDLayout.Selection {
        switch self {
        case .commandDeck, .hive, .planetary: .nearest
        default: .angular
        }
    }

    /// How long the chosen button shows as fired before the HUD closes. The Stargate's
    /// event horizon needs a moment to open.
    public var fireDuration: Double {
        switch self {
        case .stargate: 0.45
        case .constellation, .planetary: 0.2
        default: 0.12
        }
    }
}

/// Size presets for the HUD.
public enum HUDSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var title: String { rawValue.capitalized }
    public var scale: Double {
        switch self {
        case .small: 0.8
        case .medium: 1.0
        case .large: 1.2
        }
    }
}

/// Where the HUD opens.
public enum HUDAnchor: String, Codable, CaseIterable, Sendable {
    case pointer, screenCenter

    public var title: String {
        switch self {
        case .pointer: "Pointer"
        case .screenCenter: "Screen center"
        }
    }
}

/// How the keyboard shortcut behaves.
public enum HotKeyMode: String, Codable, CaseIterable, Sendable {
    /// Hold the keys, point, let go to run. A quick tap leaves the HUD open to click in.
    case hold
    /// Press once to open, again (or Esc) to close.
    case toggle

    public var title: String {
        switch self {
        case .hold: "Hold"
        case .toggle: "Toggle"
        }
    }

    public var detail: String {
        switch self {
        case .hold: "Hold the keys, point at a button and let go to run it. Tap the keys instead and the HUD stays open for you to click."
        case .toggle: "Press once to open the HUD and click a button. Press again, or Esc, to close it."
        }
    }
}

/// The mouse gesture that opens the HUD.
public enum MouseTrigger: String, Codable, CaseIterable, Sendable {
    case holdRight, optionRight, middle, back, forward, none

    public var title: String {
        switch self {
        case .holdRight: "Hold right-click"
        case .optionRight: "⌥ + right-click"
        case .middle: "Middle button"
        case .back: "Side button (back)"
        case .forward: "Side button (forward)"
        case .none: "None"
        }
    }

    public var detail: String {
        switch self {
        case .holdRight: "Hold the right button for a moment. A quick right-click still opens the app's usual menu."
        case .optionRight: "Hold Option and right-click anywhere."
        case .middle: "Click the scroll wheel or middle button."
        case .back: "The back button on the side of many mice (button 4)."
        case .forward: "The forward button on the side of many mice (button 5)."
        case .none: "Open the HUD with the keyboard only."
        }
    }

    /// The CGEvent button number this trigger listens to: 1 right, 2 middle, 3 and 4 the
    /// side buttons.
    public var buttonNumber: Int? {
        switch self {
        case .holdRight, .optionRight: 1
        case .middle: 2
        case .back: 3
        case .forward: 4
        case .none: nil
        }
    }
}
