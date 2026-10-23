import Foundation

/// Which side of the look the button pad sits on. Left and right stack its buttons in a
/// column, above and below in a row.
public enum PadPosition: String, Codable, CaseIterable, Sendable {
    case left, right, above, below

    public var title: String { rawValue.capitalized }

    /// A column beside the look, rather than a row over or under it.
    public var isColumn: Bool { self == .left || self == .right }
}

public enum DefaultPad {
    /// Eight buttons, none of them already on the default ring; the first `defaultCount`
    /// show when the pad is turned on.
    public static var slots: [Slot] {
        let c = LensCatalog.self
        return [
            Slot(c.textLens, "recapture"), Slot(c.pasteLens, "stack"), Slot(c.expansionLens, "quicksearch"),
            Slot(c.textLens, "watch"), Slot(c.pasteLens, "snippets"), Slot(c.expansionLens, "new"),
            Slot(c.diskLens, "scan-home"), Slot(c.pasteLens, "open"),
        ]
    }

    public static let defaultCount = 4
    public static let maxCount = 8
    public static let minCount = 1

    /// The letter that runs each pad button, along the home row. The keys behind them come
    /// from the keyboard layout, so on AZERTY "A" is still the key labeled A.
    public static let keyLetters = ["A", "S", "D", "F", "G", "H", "J", "K"]
    /// Those letters' keys on a US keyboard, for when the layout can't be read.
    public static let usKeyCodes: [UInt16] = [0, 1, 2, 3, 5, 4, 38, 40]
}

/// A pad as shown: which look it belongs to (each draws its own), how many buttons the
/// ring has (the look's size can depend on it), and the pad's side and button count.
public struct PadSpec: Equatable, Sendable {
    public var look: Visualization
    public var ringCount: Int
    public var position: PadPosition
    public var count: Int

    public init(look: Visualization, ringCount: Int, position: PadPosition, count: Int) {
        self.look = look
        self.ringCount = ringCount
        self.position = position
        self.count = count
    }
}

/// The sizes one look's pad is built from. Every look draws its pad buttons in boxes of
/// these sizes, so hit testing and drawing agree.
public struct PadStyle: Sendable {
    /// One button's box in a column, and in a row.
    public var columnItem: (width: Double, height: Double)
    public var rowItem: (width: Double, height: Double)
    /// Space between buttons; negative where they nest (the Hive's cells).
    public var columnGap: Double
    public var rowGap: Double
    /// Padding inside the tray at the ends of the line of buttons, and at its sides.
    public var padding: (along: Double, across: Double)
    /// Room at the top of the tray for a title (the Command Deck's).
    public var header = 0.0
    /// Every other button moves this far across the line: a column's to the right, a row's
    /// down. Packs the Hive's cells and staggers the Constellation's stars.
    public var zigzag: (column: Double, row: Double) = (0, 0)
    /// Tied to the look by a short line. Looks without a tray leave a plain gap.
    public var tether = true
}

extension HUDLayout {
    /// The tie line's length, between the look's edge and the pad.
    public static let padTether = 22.0
    /// Space between the look and a pad without a tie line.
    public static let padSpacing = 18.0

    public static func padStyle(for look: Visualization) -> PadStyle {
        switch look {
        case .halo:
            PadStyle(columnItem: (176, 40), rowItem: (72, 79), columnGap: 8, rowGap: 8, padding: (12, 10))
        case .orbit:
            PadStyle(columnItem: (180, 40), rowItem: (76, 77), columnGap: 10, rowGap: 14, padding: (4, 4), tether: false)
        case .dial:
            PadStyle(columnItem: (196, 38), rowItem: (76, 90), columnGap: 8, rowGap: 8, padding: (12, 14))
        case .stargate:
            PadStyle(columnItem: (196, 34), rowItem: (76, 92), columnGap: 8, rowGap: 8, padding: (10, 12))
        case .commandDeck:
            PadStyle(columnItem: (150, 40), rowItem: (86, 62), columnGap: 6, rowGap: 6, padding: (10, 10), header: 22)
        case .hive:
            // Cells nest like a honeycomb: three quarters of a cell apart down a column, half a
            // cell apart along a row, every other one shifted across.
            PadStyle(columnItem: (66, 74), rowItem: (66, 74), columnGap: -16, rowGap: -31, padding: (0, 0),
                     zigzag: (35, 58), tether: false)
        case .redAlert:
            PadStyle(columnItem: (150, 34), rowItem: (86, 58), columnGap: 6, rowGap: 6, padding: (8, 8))
        case .constellation:
            PadStyle(columnItem: (180, 36), rowItem: (80, 73), columnGap: 12, rowGap: 16, padding: (4, 4),
                     zigzag: (14, 12), tether: false)
        case .glassPills:
            PadStyle(columnItem: (176, 36), rowItem: (108, 36), columnGap: 8, rowGap: 6, padding: (10, 10))
        case .planetary:
            PadStyle(columnItem: (190, 42), rowItem: (80, 79), columnGap: 8, rowGap: 14, padding: (16, 12))
        }
    }

    /// How far each look's drawing reaches from its center, measured from the drawings (a
    /// lit button, labels and keycaps included), so a pad sits just clear of it.
    public static func lookExtent(_ look: Visualization, count: Int) -> Bounds {
        func around(_ r: Double) -> Bounds { Bounds(minX: -r, minY: -r, maxX: r, maxY: r) }
        switch look {
        case .halo: return around(216)
        case .orbit:
            // Names and keycaps hang under each button.
            let r = orbitRadius(count)
            return Bounds(minX: -r - 50, minY: -r - 50, maxX: r + 50, maxY: r + 70)
        case .dial: return Bounds(minX: -215, minY: -234, maxX: 215, maxY: 215)
        // The names beside the side chevrons reach past the canvas.
        case .stargate: return Bounds(minX: -340, minY: -273, maxX: 340, maxY: 274)
        case .commandDeck:
            let panel = deckPanel(count)
            return Bounds(minX: -panel.width / 2 - 4, minY: -panel.height / 2 - 4,
                          maxX: panel.width / 2 + 4, maxY: panel.height / 2 + 4)
        case .hive:
            // The cells, plus the readout under the comb.
            let cells = hive(count) + [HUDPoint(0, 0)]
            return Bounds(minX: (cells.map(\.x).min() ?? 0) - hexCell.width / 2 - 22,
                          minY: (cells.map(\.y).min() ?? 0) - hexCell.height / 2 - 22,
                          maxX: (cells.map(\.x).max() ?? 0) + hexCell.width / 2 + 22, maxY: 282)
        case .redAlert: return around(234)
        case .constellation: return around(262)
        case .glassPills:
            let r = (count <= 6 ? 126.0 : 146.0) * 1.12
            // Side pills grow outward with their names, from closer in on a small ring.
            let side = count <= 6 ? 300.0 : 330.0
            return Bounds(minX: -side, minY: -r - 34, maxX: side, maxY: r + 47)
        case .planetary: return around(280)
        }
    }

    // MARK: - Where the pad goes

    /// The tray's center and size, in the HUD's coordinates (the look's center is 0, 0).
    public static func padTray(_ pad: PadSpec) -> (center: HUDPoint, width: Double, height: Double) {
        let style = padStyle(for: pad.look)
        let n = Double(max(pad.count, 1))
        let zig = pad.count > 1 ? (pad.position.isColumn ? style.zigzag.column : style.zigzag.row) : 0
        let width: Double, height: Double
        if pad.position.isColumn {
            width = style.padding.across * 2 + style.columnItem.width + zig
            height = style.padding.along * 2 + style.header + n * style.columnItem.height + (n - 1) * style.columnGap
        } else {
            width = style.padding.along * 2 + n * style.rowItem.width + (n - 1) * style.rowGap
            height = style.padding.across * 2 + style.header + style.rowItem.height + zig
        }
        let look = lookExtent(pad.look, count: pad.ringCount)
        let gap = style.tether ? padTether : padSpacing
        switch pad.position {
        case .right: return (HUDPoint(look.maxX + gap + width / 2, 0), width, height)
        case .left: return (HUDPoint(look.minX - gap - width / 2, 0), width, height)
        case .above: return (HUDPoint(0, look.minY - gap - height / 2), width, height)
        case .below: return (HUDPoint(0, look.maxY + gap + height / 2), width, height)
        }
    }

    /// Where the tie line runs, from the look's edge to the tray.
    public static func padTether(_ pad: PadSpec) -> (from: HUDPoint, to: HUDPoint) {
        let look = lookExtent(pad.look, count: pad.ringCount)
        switch pad.position {
        case .right: return (HUDPoint(look.maxX, 0), HUDPoint(look.maxX + padTether, 0))
        case .left: return (HUDPoint(look.minX, 0), HUDPoint(look.minX - padTether, 0))
        case .above: return (HUDPoint(0, look.minY), HUDPoint(0, look.minY - padTether))
        case .below: return (HUDPoint(0, look.maxY), HUDPoint(0, look.maxY + padTether))
        }
    }

    /// Each pad button's box: its center and size.
    public static func padItems(_ pad: PadSpec) -> [(center: HUDPoint, width: Double, height: Double)] {
        let style = padStyle(for: pad.look)
        let tray = padTray(pad)
        let left = tray.center.x - tray.width / 2, top = tray.center.y - tray.height / 2 + style.header
        return (0..<max(pad.count, 0)).map { i in
            let shift = i % 2 == 1 ? (pad.position.isColumn ? style.zigzag.column : style.zigzag.row) : 0
            if pad.position.isColumn {
                let item = style.columnItem
                return (HUDPoint(left + style.padding.across + shift + item.width / 2,
                                 top + style.padding.along + item.height / 2 + Double(i) * (item.height + style.columnGap)),
                        item.width, item.height)
            }
            let item = style.rowItem
            return (HUDPoint(left + style.padding.along + item.width / 2 + Double(i) * (item.width + style.rowGap),
                             top + style.padding.across + shift + item.height / 2),
                    item.width, item.height)
        }
    }

    /// The pad button under the pointer, or nil. The margin stops halfway into the gap
    /// between buttons, so a near miss never reaches across to the next one; where boxes
    /// overlap (nested cells), the nearest button wins.
    public static func padButton(at pointer: HUDPoint, in pad: PadSpec, margin: Double = hitMargin) -> Int? {
        let style = padStyle(for: pad.look)
        let gap = pad.position.isColumn ? style.columnGap : style.rowGap
        let slack = max(0, min(margin, gap / 2))
        let hits = padItems(pad).enumerated().filter { _, f in
            abs(pointer.x - f.center.x) <= f.width / 2 + slack && abs(pointer.y - f.center.y) <= f.height / 2 + slack
        }
        return hits.min { pointer.distance(to: $0.element.center) < pointer.distance(to: $1.element.center) }?.offset
    }

    // MARK: - The whole HUD

    /// The box the HUD draws in: the canvas, grown to take in the pad if there is one.
    public static func drawingBounds(pad: PadSpec?) -> Bounds {
        let half = canvas / 2
        return Bounds(minX: -half, minY: -half, maxX: half, maxY: half).union(pad.map(padBounds))
    }

    /// The part of the HUD that must stay on screen: the look's buttons, and the pad.
    public static func visibleBounds(pad: PadSpec?, ringRadius: Double) -> Bounds {
        Bounds(minX: -ringRadius, minY: -ringRadius, maxX: ringRadius, maxY: ringRadius).union(pad.map(padBounds))
    }

    private static func padBounds(_ pad: PadSpec) -> Bounds {
        let tray = padTray(pad)
        // A little extra for a lit button, which grows.
        return Bounds(minX: tray.center.x - tray.width / 2 - 8, minY: tray.center.y - tray.height / 2 - 8,
                      maxX: tray.center.x + tray.width / 2 + 8, maxY: tray.center.y + tray.height / 2 + 8)
    }

    /// A rectangle in the HUD's coordinates (y downward).
    public struct Bounds: Equatable, Sendable {
        public var minX, minY, maxX, maxY: Double
        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
        }
        public var width: Double { maxX - minX }
        public var height: Double { maxY - minY }

        func union(_ other: Bounds?) -> Bounds {
            guard let other else { return self }
            return Bounds(minX: min(minX, other.minX), minY: min(minY, other.minY),
                          maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
        }
    }

    /// Moves a HUD centered at `(x, y)` so that `extent` around it (in Cocoa's y-up
    /// orientation, like `bounds`) stays inside `bounds`.
    public static func clamp(x: Double, y: Double, extent: Bounds,
                             bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)) -> (x: Double, y: Double) {
        func fit(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            lo > hi ? (lo + hi) / 2 : min(max(v, lo), hi)
        }
        return (fit(x, bounds.minX - extent.minX, bounds.maxX - extent.maxX),
                fit(y, bounds.minY - extent.minY, bounds.maxY - extent.maxY))
    }
}
