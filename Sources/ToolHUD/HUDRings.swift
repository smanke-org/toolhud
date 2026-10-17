import SwiftUI
import ToolHUDKit

// MARK: - 1 · Halo

/// Translucent slices around a hub; the one you point at lifts outward and glows.
struct HaloView: View {
    let model: HUDModel

    var body: some View {
        let n = max(model.slots.count, 1)
        let step = 360 / Double(n)
        let open = model.entrance()
        ZStack {
            Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).frame(width: 420, height: 420)
            ForEach(model.infos) { s in
                let lift = HUDLayout.polar(s.on ? 8 : 0, s.angle)
                let slice = AnnularSector(start: s.angle - step / 2 + 1.1, end: s.angle + step / 2 - 1.1, inner: 97, outer: 193)
                ZStack {
                    slice.fill(s.on ? s.color.opacity(min(1, model.opacity * 0.62)) : Color(white: 0.11).opacity(model.opacity))
                    slice.stroke(s.on ? s.color : Color.white.opacity(0.14), lineWidth: 1.2)
                    if s.on {
                        AnnularSector(start: s.angle - step / 2 + 2, end: s.angle + step / 2 - 2, inner: 198, outer: 201)
                            .fill(s.color)
                    }
                    SlotGlyph(symbol: s.slot.symbol, size: 20, color: s.on ? .white : .white.opacity(0.88))
                        .position(x: s.point.x, y: s.point.y - 9)
                    SlotLabel(text: s.slot.name, on: s.on, width: min(96, 2 * .pi * 146 / Double(n) - 6))
                        .position(x: s.point.x, y: s.point.y + 15)
                }
                .offset(x: lift.x, y: lift.y)
                .shadow(color: s.on ? s.color.opacity(0.6) : .clear, radius: 14)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: s.on)
            }
            Circle()
                .fill(Color(white: 0.07).opacity(min(1, model.opacity + 0.12)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .overlay(Circle().stroke(model.focusSlot?.tint.color.opacity(0.7) ?? .white.opacity(0.06), lineWidth: 1.5)
                    .padding(8))
                .frame(width: 172, height: 172)
            CenterReadout(model: model, width: 140)
                .offset(y: -12)
            SettingsGear(model: model)
        }
        .scaleEffect(0.6 + 0.4 * open)
        .opacity(min(1, open * 1.4))
    }
}

// MARK: - 3 · Orbit

/// Round buttons that spring out from the pointer, joined to the hub.
struct OrbitView: View {
    let model: HUDModel

    var body: some View {
        let mid = HUDModel.middle
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                .frame(width: HUDLayout.orbitRadius(model.slots.count) * 2, height: HUDLayout.orbitRadius(model.slots.count) * 2)
            ForEach(model.infos) { s in
                let t = model.entrance(delay: Double(s.index) * 0.035, duration: 0.42)
                let x = mid + (Double(s.point.x) - mid) * t, y = mid + (Double(s.point.y) - mid) * t
                Path { p in
                    p.move(to: CGPoint(x: mid, y: mid))
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                .stroke(s.on ? s.color.opacity(0.8) : Color.white.opacity(0.08), lineWidth: s.on ? 1.6 : 1)
                ZStack {
                    Circle()
                        .fill(s.on ? s.color.opacity(min(1, model.opacity * 0.75)) : Color(white: 0.12).opacity(model.opacity))
                        .overlay(Circle().strokeBorder(s.on ? s.color : Color.white.opacity(0.15), lineWidth: s.on ? 1.5 : 1))
                        .shadow(color: s.on ? s.color.opacity(0.5) : .black.opacity(0.45), radius: s.on ? 16 : 10, y: s.on ? 0 : 6)
                    SlotGlyph(symbol: s.slot.symbol, size: 23, color: s.on ? .white : s.color)
                }
                .frame(width: 64, height: 64)
                .scaleEffect((s.on ? 1.14 : 1) * max(t, 0.2))
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: s.on)
                .position(x: x, y: y)
                SlotLabel(text: s.slot.name, on: s.on, width: 110)
                    .position(x: x, y: y + 44)
                    .opacity(t)
            }
            Circle()
                .fill(Color(white: 0.07).opacity(min(1, model.opacity + 0.12)))
                .overlay(Circle().strokeBorder(model.focusSlot?.tint.color.opacity(0.7) ?? .white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                .frame(width: 104, height: 104)
            CenterReadout(model: model, titleFont: .system(size: 13.5, weight: .semibold), detailFont: .system(size: 9),
                          width: 90)
        }
    }
}

// MARK: - 4 · Dial

/// A rotary bezel that turns the chosen button to the pointer at the top.
struct DialView: View {
    let model: HUDModel
    private static let amber = Color(hex: "#FFC56B")

    var body: some View {
        let n = max(model.slots.count, 1)
        let step = 360 / Double(n)
        let open = model.entrance(duration: 0.4)
        ZStack {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "#3A3F4B"), Color(hex: "#15181E")], center: UnitPoint(x: 0.5, y: 0.38),
                                         startRadius: 0, endRadius: 230))
                    .opacity(model.opacity)
                    .overlay(Circle().strokeBorder(Color(hex: "#4A505E"), lineWidth: 1))
                    .frame(width: 430, height: 430)
                Ticks(count: 180, inner: 208, outer: 214).stroke(Color(hex: "#5B6271"), lineWidth: 1.3)
                Circle().stroke(Color.black.opacity(0.6), lineWidth: 2).frame(width: 404, height: 404)
                ForEach(model.infos) { s in
                    VStack(spacing: 5) {
                        SlotGlyph(symbol: s.slot.symbol, size: 20, color: s.on ? .white : .white.opacity(0.72))
                        SlotLabel(text: s.slot.name, on: s.on, size: 9.5, width: 66, uppercase: true, offColor: .white.opacity(0.72))
                        Circle().fill(s.color).frame(width: 6, height: 6)
                    }
                    .frame(width: 66, height: 76)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(s.on ? Self.amber.opacity(0.16) : .clear))
                    .position(x: HUDModel.middle, y: HUDModel.middle - 160)
                    .rotationEffect(.degrees(s.angle))
                }
            }
            .rotationEffect(.degrees(-Double(model.dialIndex) * step))
            .animation(.spring(response: 0.38, dampingFraction: 0.62), value: model.dialIndex)

            Path { p in
                p.move(to: CGPoint(x: 290, y: 66)); p.addLine(to: CGPoint(x: 310, y: 66)); p.addLine(to: CGPoint(x: 300, y: 82))
                p.closeSubpath()
            }
            .fill(Self.amber)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#262A33"), Color(hex: "#101217")], center: UnitPoint(x: 0.5, y: 0.3),
                                     startRadius: 0, endRadius: 150))
                .overlay(Circle().strokeBorder(Color(hex: "#353A46"), lineWidth: 1.5))
                .overlay(Circle().stroke(model.focusSlot?.tint.color.opacity(0.55) ?? .clear, lineWidth: 2).padding(8))
                .frame(width: 236, height: 236)
            VStack(spacing: 10) {
                SlotGlyph(symbol: model.focusSlot?.symbol ?? "dial.medium", size: 40, weight: .regular,
                          color: model.focusSlot?.tint.color ?? Self.amber)
                CenterReadout(model: model, titleFont: .system(size: 18, weight: .heavy), width: 170)
            }
        }
        .scaleEffect(0.8 + 0.2 * open)
        .opacity(min(1, open * 1.5))
    }
}

// MARK: - 5 · Stargate

/// A gate whose chevrons are the buttons. Pointing lights a chevron; choosing one spins the
/// glyph ring, locks the chevron and opens the event horizon.
struct StargateView: View {
    let model: HUDModel
    private static let lamp = Color(hex: "#FF8A1F")

    var body: some View {
        let fire = model.fireProgress(0.45)
        let firing = model.fired != nil
        let open = model.entrance(duration: 0.45)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#6B6F78"), Color(hex: "#3B3E45"), Color(hex: "#1F2126")],
                                     center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 200))
                .opacity(model.opacity)
                .overlay(Circle().strokeBorder(Color(hex: "#15161A"), lineWidth: 2))
                .frame(width: 394, height: 394)
            Circle().stroke(Color(hex: "#26282E"), lineWidth: 2).frame(width: 370, height: 370)
            Circle().fill(Color(hex: "#2A2C32").opacity(model.opacity)).frame(width: 306, height: 306)
            GateGlyphs()
                .stroke(Color(hex: "#A9ADB6").opacity(0.8), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(model.time * 4 + fire * 260))
            Circle()
                .fill(Color(hex: "#101216"))
                .overlay(Circle().strokeBorder(Color(hex: "#55585F"), lineWidth: 3))
                .frame(width: 250, height: 250)
            EventHorizon(time: model.time, strength: firing ? 0.95 : (model.highlighted != nil ? 0.22 : 0),
                         burst: firing ? fire : 1)
                .frame(width: 246, height: 246)
            ForEach(model.infos) { s in
                let lit = s.on || s.fired
                ChevronShape()
                    .fill(Color(hex: "#2F3137"))
                    .overlay(ChevronShape().stroke(Color(hex: "#0D0E11"), lineWidth: 2))
                    .overlay(ChevronLamp().fill(s.fired ? Color(hex: "#FFD27A") : lit ? Self.lamp : Color(hex: "#5A2A0E")))
                    .shadow(color: lit ? Self.lamp.opacity(0.9) : .clear, radius: 10)
                    .frame(width: 56, height: 60)
                    .position(x: HUDModel.middle, y: HUDModel.middle - 170)
                    .rotationEffect(.degrees(s.angle))
                ZStack {
                    Circle().fill(lit ? Self.lamp.opacity(0.18) : Color(white: 0.08).opacity(0.85))
                        .overlay(Circle().strokeBorder(lit ? Self.lamp : Color(hex: "#34363C"), lineWidth: 1.5))
                    SlotGlyph(symbol: s.slot.symbol, size: 16, color: lit ? Color(hex: "#FFD9AD") : s.color)
                }
                .frame(width: 36, height: 36)
                .position(s.point)
                let side = sin(s.angle * .pi / 180)
                let labelPoint = canvasPoint(255, s.angle)
                SlotLabel(text: s.slot.name, on: lit, size: 11, width: 92)
                    .multilineTextAlignment(abs(side) < 0.3 ? .center : side > 0 ? .leading : .trailing)
                    .frame(width: 92, alignment: abs(side) < 0.3 ? .center : side > 0 ? .leading : .trailing)
                    .position(x: labelPoint.x + (abs(side) < 0.3 ? 0 : side > 0 ? 36 : -36),
                              y: labelPoint.y + (abs(side) < 0.3 ? (Double(labelPoint.y) > HUDModel.middle ? 4 : -4) : 0))
            }
            VStack(spacing: 4) {
                Text(firing ? "CHEVRON \((model.fired ?? 0) + 1) LOCKED" : model.highlighted.map { "CHEVRON \($0 + 1)" } ?? "DIAL A FEATURE")
                    .font(.system(size: 10.5, weight: .bold, design: .serif)).tracking(2.5)
                    .foregroundStyle(firing ? Color(hex: "#0B2A66") : Color(hex: "#FF9A3D"))
                CenterReadout(model: model, titleFont: .system(size: 17, weight: .semibold),
                              titleColor: firing ? Color(hex: "#06204D") : .white,
                              detailColor: firing ? Color(hex: "#0B2A66") : .white.opacity(0.6), width: 170)
            }
        }
        .scaleEffect(0.85 + 0.15 * open)
        .opacity(min(1, open * 1.5))
    }
}

/// Abstract marks around the gate's inner track (our own, not the film's symbols).
struct GateGlyphs: Shape {
    private static let strokes: [(Double, Double, Double, Double)] = [
        (-4, -5, 4, -5), (-4, 5, 4, 5), (-4, -5, -4, 5), (4, -5, 4, 5), (-4, -5, 4, 5), (4, -5, -4, 5),
        (0, -6, 0, 6), (-5, 0, 5, 0), (-3, -2, 0, -6), (0, -6, 3, -2), (-3, 3, 0, 6), (0, 6, 3, 3),
    ]

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for k in 0..<36 {
            let a = Double(k) * 10 * .pi / 180
            let gx = c.x + 169 * sin(a), gy = c.y - 169 * cos(a)
            var seed = (k * 7919 + 13) % 4096
            for _ in 0..<3 {
                seed = (seed * 1103 + 12345) % 4096
                let (x0, y0, x1, y1) = Self.strokes[seed % Self.strokes.count]
                func map(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: gx + x * cos(a) - y * sin(a), y: gy + x * sin(a) + y * cos(a))
                }
                p.move(to: map(x0, y0))
                p.addLine(to: map(x1, y1))
            }
            // A divider between marks.
            let b = a + 5 * .pi / 180
            p.move(to: CGPoint(x: c.x + 154 * sin(b), y: c.y - 154 * cos(b)))
            p.addLine(to: CGPoint(x: c.x + 184 * sin(b), y: c.y - 184 * cos(b)))
        }
        return p
    }
}

/// The housing of a chevron, pointing at the gate's center.
struct ChevronShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addLines([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.maxX - r.width * 0.2, y: r.maxY * 0.82), CGPoint(x: r.minX + r.width * 0.2, y: r.maxY * 0.82)])
        p.closeSubpath()
        return p
    }
}

/// The V-shaped light inside a chevron.
struct ChevronLamp: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.addLines([CGPoint(x: w * 0.12, y: h * 0.1), CGPoint(x: w * 0.5, y: h * 0.62), CGPoint(x: w * 0.88, y: h * 0.1),
                    CGPoint(x: w * 0.68, y: h * 0.1), CGPoint(x: w * 0.5, y: h * 0.36), CGPoint(x: w * 0.32, y: h * 0.1)])
        p.closeSubpath()
        p.addRect(CGRect(x: w * 0.4, y: h * 0.84, width: w * 0.2, height: h * 0.16))
        return p
    }
}

/// The shimmering blue surface that fills the gate.
struct EventHorizon: View {
    let time: Double
    /// 0 hidden … 1 fully open.
    let strength: Double
    /// 0 → 1 as it bursts open after a chevron locks.
    let burst: Double

    var body: some View {
        let kick = burst < 0.25 ? 0.15 + burst / 0.25 * 0.97 : 1.12 - (burst - 0.25) / 0.75 * 0.12
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(hex: "#D9F4FF"), Color(hex: "#6CC6FF"), Color(hex: "#1F6FD1"), Color(hex: "#0B2A66")],
                                         center: .center, startRadius: 0, endRadius: 123))
            ForEach(0..<3, id: \.self) { i in
                let t = (time / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle().stroke(Color(hex: "#E8F8FF"), lineWidth: 2 - Double(i) * 0.5)
                    .scaleEffect(0.2 + 0.8 * t)
                    .opacity(0.6 * (1 - t))
            }
        }
        .scaleEffect(kick)
        .opacity(strength)
    }
}

// MARK: - 8 · Red Alert

/// Crimson blades around a hex hub; the armed blade gets hazard stripes.
struct RedAlertView: View {
    let model: HUDModel
    private static let red = Color(hex: "#FF3B4E"), amber = Color(hex: "#FFB020")

    var body: some View {
        let n = max(model.slots.count, 1)
        let step = 360 / Double(n)
        let open = model.entrance(duration: 0.38)
        let blink = model.fired != nil && Int(model.time * 8) % 2 == 0
        ZStack {
            ForEach(0..<24, id: \.self) { i in
                AnnularSector(start: Double(i) * 15 + 2, end: Double(i) * 15 + 11, inner: 226, outer: 233)
                    .fill(Self.red.opacity(0.55))
            }
            .rotationEffect(.degrees(model.time * 6))
            Circle().stroke(Self.amber.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [14, 6, 2, 6]))
                .frame(width: 430, height: 430)
                .rotationEffect(.degrees(-model.time * 16))
            ForEach(model.infos) { s in
                let blade = Blade(start: s.angle - step / 2 + 2.2, end: s.angle + step / 2 - 2.2, inner: 125, outer: 205)
                ZStack {
                    blade.fill(s.on ? Self.red.opacity(0.32 * max(model.opacity, 0.5) + 0.1) : Self.red.opacity(0.07 + 0.08 * model.opacity))
                    if s.on {
                        HazardStripes().stroke(Self.amber.opacity(0.3), lineWidth: 5).clipShape(blade)
                    }
                    blade.stroke(s.on ? Self.red : Self.red.opacity(0.45), lineWidth: 1.4)
                    AnnularSector(start: s.angle - 4, end: s.angle + 4, inner: 208, outer: 213)
                        .fill(s.on ? Self.amber : Self.red.opacity(0.5))
                    SlotGlyph(symbol: s.slot.symbol, size: 19, color: s.on ? .white : Color(hex: "#FFB3BA"))
                        .position(canvasPoint(178, s.angle))
                    SlotLabel(text: s.slot.name, on: s.on, size: 9.5, width: min(84, 2 * .pi * 150 / Double(n) - 6),
                              font: .monospaced, uppercase: true, offColor: Color(hex: "#FFB3BA"))
                        .position(canvasPoint(148, s.angle))
                }
                .shadow(color: s.on ? Self.red.opacity(0.8) : .clear, radius: 10)
            }
            Hexagon()
                .fill(Color(hex: "#140708"))
                .overlay(Hexagon().stroke(Self.red, lineWidth: 2))
                .overlay(Hexagon().stroke(Self.red.opacity(0.35), lineWidth: 1).padding(10))
                .frame(width: 200, height: 230)
                .rotationEffect(.degrees(30))
            VStack(spacing: 6) {
                Text(model.fired != nil ? "▲ ENGAGED ▲" : model.highlighted.map { "ARMED · \(String(format: "%02d", $0 + 1))" } ?? "SAFE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3)
                    .foregroundStyle(Self.amber)
                    .opacity(blink ? 0.15 : 1)
                CenterReadout(model: model, titleFont: .system(size: 18, weight: .heavy, design: .monospaced),
                              detailFont: .system(size: 9, design: .monospaced), detailColor: Color(hex: "#FFB3BA").opacity(0.85),
                              uppercase: true, width: 150)
            }
        }
        .scaleEffect(0.7 + 0.3 * open)
        .rotationEffect(.degrees(-20 * (1 - open)))
        .opacity(min(1, open * 1.5))
    }
}

/// A slice with cut outer corners and a notch pointing at the hub.
struct Blade: Shape {
    var start: Double, end: Double, inner: Double, outer: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func pt(_ r: Double, _ deg: Double) -> CGPoint {
            let a = deg * .pi / 180
            return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
        }
        let mid = (start + end) / 2
        var p = Path()
        p.addLines([pt(inner, start + 1.5), pt(outer - 12, start), pt(outer, start + 5), pt(outer, end - 5),
                    pt(outer - 12, end), pt(inner, end - 1.5), pt(inner + 10, mid)])
        p.closeSubpath()
        return p
    }
}

/// Diagonal stripes across the whole canvas, to clip into a shape.
struct HazardStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = -rect.height
        while x < rect.width {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 12
        }
        return p
    }
}
