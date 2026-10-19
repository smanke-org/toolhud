import AppKit
import SwiftUI
import ToolHUDKit

/// The HUD as drawn in its panel, with a dark shadow so it stands out on a busy desktop.
struct HUDRootView: View {
    let model: HUDModel

    /// Room around the drawing for the shadow, which reaches about 100 points out.
    static let shadowMargin = 110.0

    var body: some View {
        let side = HUDLayout.canvas
        HUDDrawing(model: model)
            .frame(width: side, height: side)
            .scaleEffect(model.scale)
            .frame(width: side * model.scale, height: side * model.scale)
            // A tight contact shadow under a wide soft one, the same size at every Size
            // setting. Drawn from the composited HUD so overlapping pieces cast one shadow.
            .compositingGroup()
            .shadow(color: .black.opacity(1.0), radius: 6)
            .shadow(color: .black.opacity(0.8), radius: 50)
            .frame(width: side * model.scale + Self.shadowMargin * 2, height: side * model.scale + Self.shadowMargin * 2)
    }
}

/// The chosen visualization at its native size.
struct HUDDrawing: View {
    let model: HUDModel

    var body: some View {
        Group {
            switch model.visualization {
            case .halo: HaloView(model: model)
            case .orbit: OrbitView(model: model)
            case .dial: DialView(model: model)
            case .stargate: StargateView(model: model)
            case .commandDeck: CommandDeckView(model: model)
            case .hive: HiveView(model: model)
            case .redAlert: RedAlertView(model: model)
            case .constellation: ConstellationView(model: model)
            case .glassPills: GlassPillsView(model: model)
            case .planetary: PlanetaryView(model: model)
            }
        }
        .frame(width: HUDLayout.canvas, height: HUDLayout.canvas)
        .allowsHitTesting(false)
    }
}

// MARK: - What each button needs to be drawn

struct SlotInfo: Identifiable {
    let index: Int
    let slot: Slot
    /// Its center on the 600-point canvas.
    let point: CGPoint
    /// Degrees clockwise from up.
    let angle: Double
    let on: Bool
    let fired: Bool
    let color: Color
    var id: Int { index }
}

extension HUDModel {
    nonisolated static let middle = HUDLayout.canvas / 2

    var infos: [SlotInfo] {
        let centers = self.centers
        return slots.enumerated().map { i, slot in
            let c = i < centers.count ? centers[i] : HUDPoint(0, 0)
            return SlotInfo(index: i, slot: slot, point: CGPoint(x: Self.middle + c.x, y: Self.middle + c.y),
                            angle: HUDLayout.angle(of: i, count: slots.count),
                            on: highlighted == i, fired: fired == i, color: slot.tint.color)
        }
    }

    /// 0 → 1 as the HUD opens, with a small overshoot; `delay` staggers buttons.
    func entrance(delay: Double = 0, duration: Double = 0.32) -> Double {
        let t = min(max((time - delay) / duration, 0), 1)
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    /// 0 → 1 over `duration` after a button fired.
    func fireProgress(_ duration: Double) -> Double {
        guard fired != nil else { return 0 }
        return min(max((time - firedAt) / duration, 0), 1)
    }

    var focusSlot: Slot? { focus.flatMap { $0 < slots.count ? slots[$0] : nil } }

    /// The readout's three lines for the button in focus.
    var readout: (title: String, app: String, detail: String) {
        if gearHovered && fired == nil { return ("Settings", "ToolHUD", "Buttons, looks and triggers") }
        guard let slot = focusSlot else {
            return ("ToolHUD", "Click a button", "Esc closes · 1–\(min(slots.count, 9)) pick")
        }
        if fired != nil { return (slot.name, slot.appName ?? "Keystroke", "Running…") }
        return (slot.name, slot.appName ?? "Keystroke", slot.summary)
    }
}

/// A point `radius` from the canvas center, `degrees` clockwise from up.
func canvasPoint(_ radius: Double, _ degrees: Double) -> CGPoint {
    let p = HUDLayout.polar(radius, degrees)
    return CGPoint(x: HUDModel.middle + p.x, y: HUDModel.middle + p.y)
}

// MARK: - Shapes

/// A slice of a ring, from `start` to `end` degrees clockwise from up.
struct AnnularSector: Shape {
    var start: Double, end: Double, inner: Double, outer: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        // SwiftUI's y points down, so increasing angles run clockwise on screen.
        p.addArc(center: c, radius: outer, startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .degrees(end - 90), endAngle: .degrees(start - 90), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// A rectangle with its corners cut off, the house shape for the sci-fi looks.
struct Chamfer: Shape {
    var cut: Double = 10
    /// Only the top-left and bottom-right corners, as on a keycap.
    var twoCorners = true

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - (twoCorners ? 0 : cut), y: r.minY))
        if !twoCorners { p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut)) }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + (twoCorners ? 0 : cut), y: r.maxY))
        if !twoCorners { p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut)) }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }
}

/// A pointy-topped hexagon filling its frame's height.
struct Hexagon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let points = [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY + r.height * 0.25),
                      CGPoint(x: r.maxX, y: r.minY + r.height * 0.75), CGPoint(x: r.midX, y: r.maxY),
                      CGPoint(x: r.minX, y: r.minY + r.height * 0.75), CGPoint(x: r.minX, y: r.minY + r.height * 0.25)]
        p.addLines(points)
        p.closeSubpath()
        return p
    }
}

/// Short radial tick marks around a circle.
struct Ticks: Shape {
    var count: Int
    var inner: Double, outer: Double
    /// Every `longEvery`th tick starts at `longInner` instead.
    var longEvery = 0
    var longInner = 0.0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            let r0 = longEvery > 0 && i % longEvery == 0 ? longInner : inner
            p.move(to: CGPoint(x: c.x + r0 * sin(a), y: c.y - r0 * cos(a)))
            p.addLine(to: CGPoint(x: c.x + outer * sin(a), y: c.y - outer * cos(a)))
        }
        return p
    }
}

// MARK: - Pieces

/// The small gear that opens Settings, drawn where `HUDLayout.gearCenter` says, in the
/// look's own colors. It fills with `tint` and grows a little when pointed at.
struct SettingsGear: View {
    let model: HUDModel
    var size: Double = 13
    var tint: Color = .white
    /// The gear's color while pointed at, on the `tint` fill.
    var litGlyph: Color = .black.opacity(0.85)
    /// A rounded square instead of a circle, for the keycap look.
    var square = false

    var body: some View {
        if let gear = HUDLayout.gearCenter(for: model.visualization, count: model.slots.count) {
            let on = model.gearHovered
            let shape = RoundedRectangle(cornerRadius: square ? 6 : size, style: .continuous)
            Image(systemName: "gearshape.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? litGlyph : tint.opacity(0.6))
                .frame(width: size * 2, height: size * 2)
                .background(shape.fill(on ? tint : tint.opacity(0.09)))
                .overlay(shape.strokeBorder(tint.opacity(on ? 0 : 0.22), lineWidth: 1))
                .shadow(color: on ? tint.opacity(0.6) : .clear, radius: 8)
                .scaleEffect(on ? 1.12 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.65), value: on)
                .position(x: HUDModel.middle + gear.x, y: HUDModel.middle + gear.y)
                .accessibilityLabel("Settings")
        }
    }
}

/// A button's SF Symbol, or a plain circle if the name isn't one.
struct SlotGlyph: View {
    let symbol: String
    var size: Double = 20
    var weight: Font.Weight = .semibold
    var color: Color = .white

    var body: some View {
        let name = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "circle" : symbol
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
    }
}

/// The three lines in the middle: the button's name, its app and what it does.
struct CenterReadout: View {
    let model: HUDModel
    var titleFont: Font = .system(size: 17, weight: .semibold)
    var detailFont: Font = .system(size: 10.5)
    var titleColor: Color = .white
    var detailColor: Color = .white.opacity(0.62)
    var uppercase = false
    var width: Double = 150

    var body: some View {
        let r = model.readout
        let tint = model.focusSlot?.tint.color ?? .white.opacity(0.7)
        VStack(spacing: 4) {
            Text(uppercase ? r.title.uppercased() : r.title)
                .font(titleFont).foregroundStyle(titleColor)
                .lineLimit(2).multilineTextAlignment(.center)
            Text(uppercase ? r.app.uppercased() : r.app)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                .lineLimit(1)
            Text(r.detail)
                .font(detailFont).foregroundStyle(detailColor)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: width)
        .minimumScaleFactor(0.7)
    }
}

/// A button's name under or beside its icon.
struct SlotLabel: View {
    let text: String
    var on = false
    var size: Double = 11.5
    var width: Double = 96
    var font: Font.Design = .default
    var uppercase = false
    var offColor: Color = .white.opacity(0.82)

    var body: some View {
        Text(uppercase ? text.uppercased() : text)
            .font(.system(size: size, weight: on ? .semibold : .medium, design: font))
            .tracking(uppercase ? 0.8 : 0)
            .foregroundStyle(on ? Color.white : offColor)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: width)
    }
}

/// The number key that picks a button, drawn as a small keycap: 1–9, then 0 for the tenth.
struct SlotKeyCap: View {
    let index: Int
    var on = false
    var tint: Color = .white

    static func key(for index: Int) -> String? {
        switch index {
        case 0..<9: return "\(index + 1)"
        case 9: return "0"
        default: return nil
        }
    }

    var body: some View {
        if let key = Self.key(for: index) {
            let shape = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(on ? Color.white : tint.opacity(0.85))
                .frame(minWidth: 16, minHeight: 15)
                .background(shape.fill(tint.opacity(on ? 0.3 : 0.13)))
                .overlay(shape.strokeBorder(tint.opacity(on ? 0.45 : 0.22), lineWidth: 0.5))
                // A thicker bottom edge, like a key's front lip.
                .overlay(alignment: .bottom) {
                    shape.fill(tint.opacity(on ? 0.4 : 0.2)).frame(height: 1.5).padding(.horizontal, 1.5)
                }
                .accessibilityLabel("Key \(key)")
        }
    }
}

extension Color {
    init(hex: String) {
        let c = SlotColor(hex: hex) ?? .neutral
        self = c.color
    }
}
