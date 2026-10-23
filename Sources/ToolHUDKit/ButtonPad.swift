import Foundation

/// Which side of the Halo the button pad sits on. Left and right stack its buttons in a
/// column, above and below in a row.
public enum PadPosition: String, Codable, CaseIterable, Sendable {
    case left, right, above, below

    public var title: String { rawValue.capitalized }

    /// A column beside the halo, rather than a row over or under it.
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

/// The Halo's button pad: a tray of round buttons tied to the halo by a short line.
extension HUDLayout {
    /// Where the halo's drawing ends (its outer hairline is at 210) and the tie line starts.
    public static let padTetherStart = 214.0
    /// Where the tray starts, past the tie line.
    public static let padGap = 236.0
    public static let padCoin = 40.0

    // A column: each row is a coin, the name and the key, `padRowGap` apart.
    public static let padRowGap = 8.0
    public static let padLabelWidth = 96.0
    /// Padding, coin, gap, name, gap, keycap, padding.
    public static let padColumnWidth = 12 + padCoin + 10 + padLabelWidth + 8 + 16 + 14

    // A row: each item is a coin over its name and key.
    public static let padItemWidth = 72.0
    public static let padItemHeight = padCoin + 5 + 14 + 5 + 15
    public static let padItemGap = 8.0

    /// The tray's center and size, in the HUD's coordinates (the halo's center is 0, 0).
    public static func padTray(count: Int, position: PadPosition) -> (center: HUDPoint, width: Double, height: Double) {
        let n = Double(max(count, 1))
        let width = position.isColumn ? padColumnWidth : 14 * 2 + n * padItemWidth + (n - 1) * padItemGap
        let height = position.isColumn ? 12 * 2 + n * padCoin + (n - 1) * padRowGap : 12 * 2 + padItemHeight
        switch position {
        case .right: return (HUDPoint(padGap + width / 2, 0), width, height)
        case .left: return (HUDPoint(-padGap - width / 2, 0), width, height)
        case .above: return (HUDPoint(0, -padGap - height / 2), width, height)
        case .below: return (HUDPoint(0, padGap + height / 2), width, height)
        }
    }

    /// Each pad button's coin center.
    public static func padCoins(count: Int, position: PadPosition) -> [HUDPoint] {
        let tray = padTray(count: count, position: position)
        let left = tray.center.x - tray.width / 2, top = tray.center.y - tray.height / 2
        return (0..<max(count, 0)).map { i in
            let i = Double(i)
            return position.isColumn
                ? HUDPoint(left + 12 + padCoin / 2, top + 12 + padCoin / 2 + i * (padCoin + padRowGap))
                : HUDPoint(left + 14 + padItemWidth / 2 + i * (padItemWidth + padItemGap), top + 12 + padCoin / 2)
        }
    }

    /// The area that counts as a pad button: its whole row in a column (coin, name and
    /// key), its coin with the name and key under it in a row.
    public static func padButtonFrame(_ index: Int, count: Int, position: PadPosition) -> (center: HUDPoint, width: Double, height: Double) {
        let coin = padCoins(count: count, position: position)[index]
        if position.isColumn {
            let tray = padTray(count: count, position: position)
            return (HUDPoint(tray.center.x, coin.y), tray.width - 16, padCoin)
        }
        return (HUDPoint(coin.x, coin.y - padCoin / 2 + padItemHeight / 2), padItemWidth, padItemHeight)
    }

    /// The pad button under the pointer, or nil. The margin stops halfway into the gap
    /// between buttons, so a near miss never reaches across to the next one.
    public static func padButton(at pointer: HUDPoint, count: Int, position: PadPosition, margin: Double = hitMargin) -> Int? {
        let slack = min(margin, (position.isColumn ? padRowGap : padItemGap) / 2)
        for i in 0..<max(count, 0) {
            let f = padButtonFrame(i, count: count, position: position)
            if abs(pointer.x - f.center.x) <= f.width / 2 + slack && abs(pointer.y - f.center.y) <= f.height / 2 + slack {
                return i
            }
        }
        return nil
    }

    /// The box the HUD draws in: the canvas, grown to take in the pad if there is one.
    public static func drawingBounds(pad: (position: PadPosition, count: Int)?) -> Bounds {
        let half = canvas / 2
        return Bounds(minX: -half, minY: -half, maxX: half, maxY: half).union(pad.map { padBounds($0) })
    }

    /// The part of the HUD that must stay on screen: the halo's buttons, and the pad.
    public static func visibleBounds(pad: (position: PadPosition, count: Int)?, ringRadius: Double) -> Bounds {
        Bounds(minX: -ringRadius, minY: -ringRadius, maxX: ringRadius, maxY: ringRadius).union(pad.map { padBounds($0) })
    }

    private static func padBounds(_ pad: (position: PadPosition, count: Int)) -> Bounds {
        let tray = padTray(count: pad.count, position: pad.position)
        // A little extra for the lit coin, which grows.
        return Bounds(minX: tray.center.x - tray.width / 2 - 6, minY: tray.center.y - tray.height / 2 - 6,
                      maxX: tray.center.x + tray.width / 2 + 6, maxY: tray.center.y + tray.height / 2 + 6)
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
