import Foundation

/// A point in the HUD's own coordinates: points, measured from the HUD's center, x to the
/// right and y downward (as SwiftUI draws).
public struct HUDPoint: Hashable, Sendable {
    public var x: Double, y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    public var length: Double { (x * x + y * y).squareRoot() }
    public func distance(to other: HUDPoint) -> Double { HUDPoint(x - other.x, y - other.y).length }
}

/// Where every visualization puts its buttons, and which button the pointer is choosing.
///
/// The views draw from these positions and the controller selects from them, so what you
/// see lit is always what runs. Every visualization is drawn in a `canvas`-point square
/// and scaled for the Size setting.
public enum HUDLayout {
    public static let canvas = 600.0
    /// Pointing inside this radius chooses nothing (and clicking there closes the HUD).
    public static let deadZone = 44.0

    public enum Selection: Sendable {
        /// By direction from the center, as in a marking menu: aim, don't hunt.
        case angular
        /// The closest button, within reach.
        case nearest
    }

    // MARK: - Angles

    /// Button `index` of `count` sits at this many degrees clockwise from straight up.
    public static func angle(of index: Int, count: Int) -> Double {
        Double(index) * 360 / Double(max(count, 1))
    }

    /// Degrees clockwise from straight up, in 0..<360, for a direction (y downward).
    public static func bearing(of point: HUDPoint) -> Double {
        let degrees = atan2(point.x, -point.y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// The button whose slice contains this direction.
    public static func index(forBearing degrees: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = 360 / Double(count)
        let shifted = (degrees + step / 2).truncatingRemainder(dividingBy: 360)
        return min(Int(shifted / step), count - 1)
    }

    /// A position `radius` from the center at `degrees` clockwise from up.
    public static func polar(_ radius: Double, _ degrees: Double) -> HUDPoint {
        let r = degrees * .pi / 180
        return HUDPoint(radius * sin(r), -radius * cos(r))
    }

    // MARK: - Selection

    /// The button the pointer chooses: for `.angular`, nil inside the dead zone; for
    /// `.nearest` (whose grids can have a button at the very center), nil away from every
    /// button.
    public static func selection(at pointer: HUDPoint, centers: [HUDPoint], style: Selection,
                                 reach: Double = 72) -> Int? {
        guard !centers.isEmpty else { return nil }
        switch style {
        case .angular:
            guard pointer.length > deadZone else { return nil }
            return index(forBearing: bearing(of: pointer), count: centers.count)
        case .nearest:
            let best = centers.enumerated().min { $0.element.distance(to: pointer) < $1.element.distance(to: pointer) }
            guard let best, best.element.distance(to: pointer) <= reach else { return nil }
            return best.offset
        }
    }

    // MARK: - Settings gear

    /// How close the pointer must be to the gear to point at it.
    public static let gearReach = 15.0

    /// Where a look draws its Settings gear: in a quiet spot of the look itself, clear of
    /// the buttons, so aiming at a button never passes over it.
    public static func gearCenter(for visualization: Visualization, count: Int) -> HUDPoint? {
        switch visualization {
        case .halo: HUDPoint(0, 52)
        case .orbit: HUDPoint(0, 78)
        case .dial: HUDPoint(0, 90)
        case .stargate: HUDPoint(0, 94)
        case .redAlert: HUDPoint(0, 84)
        case .constellation: HUDPoint(0, -66)
        case .glassPills: HUDPoint(0, 76)
        case .planetary: HUDPoint(0, 66)
        case .hive: HUDPoint(0, 33)
        case .commandDeck:
            // At the right end of the panel's header.
            { let panel = deckPanel(count); return HUDPoint(panel.width / 2 - 36, -panel.height / 2 + 23) }()
        }
    }

    /// Whether the pointer is on the gear. Checked before the buttons, so it wins where
    /// the two overlap.
    public static func pointsAtGear(_ pointer: HUDPoint, in visualization: Visualization, count: Int) -> Bool {
        guard let gear = gearCenter(for: visualization, count: count) else { return false }
        return pointer.distance(to: gear) <= gearReach
    }

    // MARK: - Positions

    /// Where each button's center is drawn. `phase` (degrees) turns the Planetary orbits.
    public static func centers(for visualization: Visualization, count: Int, phase: Double = 0) -> [HUDPoint] {
        let n = max(count, 0)
        switch visualization {
        case .halo: return ring(n, radius: 146)
        case .orbit: return ring(n, radius: orbitRadius(n))
        case .dial: return ring(n, radius: 160)
        case .stargate: return ring(n, radius: 222)
        case .redAlert: return ring(n, radius: 165)
        case .glassPills: return ring(n, radius: n <= 6 ? 126 : 146, yStretch: 1.12)
        case .constellation:
            return (0..<n).map { polar($0 % 2 == 0 ? 143 : 197, angle(of: $0, count: n)) }
        case .commandDeck: return deck(n)
        case .hive: return hive(n)
        case .planetary: return planets(n, phase: phase).map(\.center)
        }
    }

    public static func ring(_ count: Int, radius: Double, yStretch: Double = 1) -> [HUDPoint] {
        (0..<count).map { i in
            let p = polar(radius, angle(of: i, count: count))
            return HUDPoint(p.x, p.y * yStretch)
        }
    }

    public static func orbitRadius(_ count: Int) -> Double {
        count <= 4 ? 133 : count <= 8 ? 167 : 190
    }

    // MARK: Command Deck

    public static let keySize = (width: 96.0, height: 80.0)
    public static let keyGap = 10.0

    public static func deckColumns(_ count: Int) -> Int {
        count <= 3 ? max(count, 1) : count == 4 ? 2 : count <= 6 ? 3 : 4
    }

    /// The Command Deck's panel: the keys plus margins, a header and a footer.
    public static func deckPanel(_ count: Int) -> (width: Double, height: Double) {
        let cols = deckColumns(count)
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        let gridW = Double(cols) * keySize.width + Double(cols - 1) * keyGap
        let gridH = Double(rows) * keySize.height + Double(max(rows - 1, 0)) * keyGap
        return (max(gridW + 44, 300), gridH + 44 + 46 + 40)
    }

    public static func deck(_ count: Int) -> [HUDPoint] {
        let cols = deckColumns(count)
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        let w = Double(cols) * keySize.width + Double(cols - 1) * keyGap
        let h = Double(rows) * keySize.height + Double(max(rows - 1, 0)) * keyGap
        return (0..<count).map { i in
            let col = Double(i % cols), row = Double(i / cols)
            return HUDPoint(-w / 2 + keySize.width / 2 + col * (keySize.width + keyGap),
                            -h / 2 + keySize.height / 2 + row * (keySize.height + keyGap))
        }
    }

    // MARK: Hive

    /// Axial hex coordinates: the six neighbors first, then the six cells in their gaps.
    public static let hexSpots: [(q: Int, r: Int)] = [
        (1, -1), (1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1),
        (1, -2), (2, -1), (1, 1), (-1, 2), (-2, 1), (-1, -1),
    ]
    /// A pointy-top hex cell's width and height, gaps included.
    public static let hexCell = (width: 92.0, height: 106.0)

    public static func hive(_ count: Int) -> [HUDPoint] {
        hexSpots.prefix(count).map { spot in
            HUDPoint(hexCell.width * (Double(spot.q) + Double(spot.r) / 2), hexCell.height * 0.75 * Double(spot.r))
        }
    }

    // MARK: Planetary

    public struct Planet: Sendable {
        public var index: Int
        public var center: HUDPoint
        public var outer: Bool
        public var size: Double
    }

    public static let planetOrbits = (inner: 125.0, outer: 208.0)

    /// Even-numbered buttons on the inner orbit, odd on the outer, which turns the other way
    /// more slowly.
    public static func planets(_ count: Int, phase: Double) -> [Planet] {
        let innerCount = (count + 1) / 2, outerCount = count / 2
        return (0..<count).map { i in
            let outer = i % 2 == 1
            let k = i / 2
            let degrees = outer
                ? -phase * 0.575 + 180 / Double(max(outerCount, 1)) + Double(k) * 360 / Double(max(outerCount, 1))
                : phase + Double(k) * 360 / Double(max(innerCount, 1))
            let radius = outer ? planetOrbits.outer : planetOrbits.inner
            return Planet(index: i, center: polar(radius, degrees), outer: outer, size: 42 + Double((i * 7) % 14))
        }
    }

    // MARK: - Placement on screen

    /// Moves a HUD centered at `(x, y)` with this radius so it stays inside `bounds`
    /// (minX, minY, maxX, maxY, in any coordinate system with the same orientation).
    public static func clamp(x: Double, y: Double, radius: Double,
                             bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)) -> (x: Double, y: Double) {
        func fit(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi)
        }
        return (fit(x, bounds.minX + radius, bounds.maxX - radius), fit(y, bounds.minY + radius, bounds.maxY - radius))
    }
}
