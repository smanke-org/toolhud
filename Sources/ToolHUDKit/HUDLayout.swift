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
    /// How far outside a button's drawn shape a click still counts, so a near miss with a
    /// trackpad isn't lost.
    public static let hitMargin = 8.0

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

    // MARK: - Hit testing

    /// The button whose drawn shape (plus `margin`) is under the pointer, or nil. Buttons
    /// are chosen only by pointing right at them, never by direction. Where two shapes'
    /// margins overlap, the nearer button wins.
    ///
    /// - Parameters:
    ///   - dialTurn: degrees the Dial's bezel has turned (counterclockwise).
    ///   - phase: the Planetary orbits' phase.
    ///   - pillWidths: each Glass Pill's measured width; a typical width is assumed for
    ///     any not measured yet.
    public static func button(at pointer: HUDPoint, in visualization: Visualization, count: Int,
                              margin: Double = hitMargin, dialTurn: Double = 0, phase: Double = 0,
                              pillWidths: [Int: Double] = [:]) -> Int? {
        let n = max(count, 0)
        guard n > 0 else { return nil }
        let step = 360 / Double(n)
        let r = pointer.length
        let bearing = bearing(of: pointer)

        /// Inside the annulus `inner...outer` and within this button's slice of angle.
        func inSlice(_ i: Int, inner: Double, outer: Double, inset: Double) -> Bool {
            guard r >= inner - margin, r <= outer + margin else { return false }
            var delta = abs(bearing - angle(of: i, count: n)).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta = 360 - delta }
            // The margin as an angle at this radius, so the gap between slices still counts.
            let slack = margin / max(r, 1) * 180 / .pi
            return delta <= step / 2 - inset + slack
        }
        func inCircle(_ c: HUDPoint, _ radius: Double) -> Bool { pointer.distance(to: c) <= radius + margin }
        func inRect(_ c: HUDPoint, _ w: Double, _ h: Double) -> Bool {
            abs(pointer.x - c.x) <= w / 2 + margin && abs(pointer.y - c.y) <= h / 2 + margin
        }
        /// A pointy-topped hexagon `w` wide and `h` tall.
        func inHex(_ c: HUDPoint, _ w: Double, _ h: Double) -> Bool {
            let w = w + margin * 2, h = h + margin * 2
            let dx = abs(pointer.x - c.x), dy = abs(pointer.y - c.y)
            return dx <= w / 2 && dy <= h / 2 - (h / 4) * (dx / (w / 2))
        }

        var hits: [(index: Int, distance: Double)] = []
        func add(_ i: Int, _ hit: Bool, _ center: HUDPoint) {
            if hit { hits.append((i, pointer.distance(to: center))) }
        }
        switch visualization {
        case .halo:
            for i in 0..<n { add(i, inSlice(i, inner: 97, outer: 201, inset: 1.1), polar(146, angle(of: i, count: n))) }
        case .redAlert:
            for i in 0..<n { add(i, inSlice(i, inner: 125, outer: 213, inset: 2.2), polar(170, angle(of: i, count: n))) }
        case .orbit:
            // The name under each button counts as part of it.
            for (i, c) in centers(for: .orbit, count: n).enumerated() {
                add(i, inCircle(c, 32) || inRect(HUDPoint(c.x, c.y + 44), 90, 16), c)
            }
        case .constellation:
            for (i, c) in centers(for: .constellation, count: n).enumerated() {
                let label = HUDPoint(c.x, c.y + (c.y > 1 ? 38 : -38))
                add(i, inCircle(c, 25) || inRect(label, 90, 16), c)
            }
        case .planetary:
            for p in planets(n, phase: phase) {
                let label = HUDPoint(p.center.x, p.center.y + p.size / 2 + 12)
                add(p.index, inCircle(p.center, p.size / 2) || inRect(label, 90, 16), p.center)
            }
        case .dial:
            for i in 0..<n {
                let c = polar(160, angle(of: i, count: n) - dialTurn)
                add(i, inCircle(c, 38), c)
            }
        case .stargate:
            for i in 0..<n {
                let a = angle(of: i, count: n)
                let chevron = polar(170, a), glyph = polar(222, a)
                add(i, inCircle(chevron, 30) || inCircle(glyph, 18), glyph)
            }
        case .commandDeck:
            for (i, c) in deck(n).enumerated() {
                let key = HUDPoint(c.x, c.y + 3)
                add(i, inRect(key, keySize.width, keySize.height), key)
            }
        case .hive:
            for (i, c) in hive(n).enumerated() { add(i, inHex(c, hexCell.width - 6, hexCell.height - 6), c) }
        case .glassPills:
            for (i, c) in centers(for: .glassPills, count: n).enumerated() {
                let pill = pillFrame(i, count: n, anchor: c, width: pillWidths[i] ?? 150)
                add(i, inRect(pill.center, pill.width, 42), pill.center)
            }
        }
        return hits.min { $0.distance < $1.distance }?.index
    }

    /// Where a Glass Pill sits: centered on its point at the top and bottom, and growing
    /// outward from it on the sides, as the view lays it out.
    public static func pillFrame(_ index: Int, count: Int, anchor: HUDPoint, width: Double) -> (center: HUDPoint, width: Double) {
        let side = sin(angle(of: index, count: count) * .pi / 180)
        if abs(side) < 0.25 { return (anchor, width) }
        // The view puts the pill's inner end 22 pt past its point, toward the center.
        let inner = side > 0 ? anchor.x - 22 : anchor.x + 22
        return (HUDPoint(side > 0 ? inner + width / 2 : inner - width / 2, anchor.y), width)
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
