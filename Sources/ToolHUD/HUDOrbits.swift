import SwiftUI
import ToolHUDKit

// MARK: - 11 · Constellation

/// Star buttons on two staggered radii, joined by lines that draw themselves in.
struct ConstellationView: View {
    let model: HUDModel

    var body: some View {
        let infos = model.infos
        let draw = model.entrance(delay: 0.1, duration: 0.8)
        ZStack {
            Starfield().fill(Color.white.opacity(0.4))
            Path { p in
                guard let first = infos.first else { return }
                p.move(to: first.point)
                for s in infos.dropFirst() { p.addLine(to: s.point) }
                p.closeSubpath()
            }
            .trim(from: 0, to: min(max(draw, 0), 1))
            .stroke(Color(hex: "#AAC8FF").opacity(0.3), lineWidth: 1)
            ForEach(infos) { s in
                let t = model.entrance(delay: Double(s.index) * 0.05, duration: 0.5)
                if s.on {
                    Path { p in
                        p.move(to: CGPoint(x: HUDModel.middle, y: HUDModel.middle))
                        p.addLine(to: s.point)
                    }
                    .stroke(s.color.opacity(0.85), lineWidth: 1.6)
                }
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: s.on ? [s.color.opacity(0.95), s.color.opacity(0.25)]
                                                          : [Color(hex: "#1E2640").opacity(model.opacity), Color(hex: "#0C101E").opacity(model.opacity)],
                                             center: .center, startRadius: 0, endRadius: 26))
                        .overlay(Circle().strokeBorder(s.color.opacity(s.on ? 0.9 : 0.45), lineWidth: 1))
                        .shadow(color: s.color.opacity(s.on ? 0.85 : 0.35), radius: s.on ? 22 : 9)
                    SlotGlyph(symbol: s.slot.symbol, size: 19, color: s.on ? .white : s.color)
                }
                .frame(width: 50, height: 50)
                .scaleEffect((s.on ? 1.18 : 1) * max(t, 0.3))
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: s.on)
                .position(s.point)
                .opacity(min(1, t * 1.5))
                let below = Double(s.point.y) > HUDModel.middle + 1
                VStack(spacing: 3) {
                    if !below { SlotLabel(text: s.slot.name, on: s.on, size: 11.5, width: 120, offColor: Color(hex: "#DCE6FF").opacity(0.72)) }
                    SlotKeyCap(index: s.index, on: s.on, tint: Color(hex: "#DCE6FF"))
                    if below { SlotLabel(text: s.slot.name, on: s.on, size: 11.5, width: 120, offColor: Color(hex: "#DCE6FF").opacity(0.72)) }
                }
                .position(x: s.point.x, y: s.point.y + (below ? 46 : -46))
                .opacity(t)
            }
            Image(systemName: "sparkle")
                .font(.system(size: 24))
                .foregroundStyle(Color(hex: "#E8F0FF"))
                .frame(width: 52, height: 52)
                .background(Circle().fill(RadialGradient(colors: [Color(hex: "#C8DCFF").opacity(0.35), Color(hex: "#141A30").opacity(0.9)],
                                                         center: .center, startRadius: 0, endRadius: 26)))
                .shadow(color: Color(hex: "#AAC8FF").opacity(0.45), radius: 20)
            CenterReadout(model: model, titleFont: .system(size: 15, weight: .bold), width: 200)
                .offset(y: 70)
            SettingsGear(model: model, size: 11, tint: Color(hex: "#C8DCFF"), litGlyph: Color(hex: "#0C101E"))
        }
    }
}

/// A fixed scatter of faint stars.
struct Starfield: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var s = 7
        for _ in 0..<110 {
            s = (s * 9301 + 49297) % 233280
            let x = Double(s) / 233280 * rect.width
            s = (s * 9301 + 49297) % 233280
            let y = Double(s) / 233280 * rect.height
            s = (s * 9301 + 49297) % 233280
            let r = 0.4 + Double(s) / 233280 * 1.0
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

// MARK: - 12 · Glass Pills

/// Labeled pills around a hub: the most readable of the looks.
struct GlassPillsView: View {
    let model: HUDModel

    var body: some View {
        let mid = HUDModel.middle
        ZStack {
            ForEach(model.infos) { s in
                let t = model.entrance(delay: Double(s.index) * 0.03, duration: 0.45)
                let side = sin(s.angle * .pi / 180)
                let centered = abs(side) < 0.25
                let alignment: Alignment = centered ? .center : side > 0 ? .leading : .trailing
                let shift = centered ? 0.0 : side > 0 ? 100 - 22 : -(100 - 22)
                pill(s)
                    .frame(width: 200, alignment: alignment)
                    .position(x: mid + (Double(s.point.x) + shift - mid) * t, y: mid + (Double(s.point.y) - mid) * t)
                    .opacity(min(1, t * 1.4))
            }
            VStack(spacing: 3) {
                Text(model.readout.title)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: "#141821"))
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(model.readout.app)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(model.focusSlot?.tint.color ?? Color(hex: "#5B6170"))
            }
            .frame(width: 84, height: 84)
            .padding(8)
            .background(Circle().fill(Color.white.opacity(min(1, model.opacity + 0.15))))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
            .minimumScaleFactor(0.7)
            // White, like the pills, with a dark gear.
            SettingsGear(model: model, size: 11, tint: Color(hex: "#141821"), litGlyph: .white)
                .background(Circle().fill(Color.white.opacity(min(1, model.opacity + 0.15))).frame(width: 26, height: 26)
                    .position(x: HUDModel.middle, y: HUDModel.middle + 76))
        }
    }

    private func pill(_ s: SlotInfo) -> some View {
        HStack(spacing: 8) {
            SlotGlyph(symbol: s.slot.symbol, size: 15, color: s.on ? .white : s.color)
                .frame(width: 30, height: 30)
                .background(Circle().fill(s.on ? Color.white.opacity(0.22) : s.color.opacity(0.16)))
            Text(s.slot.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(s.on ? Color.white : Color(hex: "#141821"))
                .lineLimit(1)
            if let key = SlotKeyCap.key(for: s.index) {
                Text(key)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(s.on ? Color.white : Color(hex: "#4A5060"))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(s.on ? Color.white.opacity(0.25) : Color.black.opacity(0.08)))
            }
        }
        .padding(.leading, 6).padding(.trailing, 12)
        .frame(height: 42)
        .background(Capsule().fill(s.on ? s.color : Color.white.opacity(model.opacity)))
        .overlay(Capsule().strokeBorder(s.on ? s.color : Color.white.opacity(0.75), lineWidth: 1))
        .shadow(color: s.on ? s.color.opacity(0.45) : .black.opacity(0.18), radius: s.on ? 14 : 10, y: 6)
        .scaleEffect(s.on ? 1.08 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: s.on)
        .fixedSize()
        .onGeometryChange(for: Double.self) { $0.size.width } action: { model.pillWidths[s.index] = $0 }
    }
}

// MARK: - 13 · Planetary

/// Planets on two orbits around a sun; they drift until you aim, then hold still.
struct PlanetaryView: View {
    let model: HUDModel

    var body: some View {
        let planets = HUDLayout.planets(model.slots.count, phase: model.phase)
        let infos = model.infos
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                .frame(width: HUDLayout.planetOrbits.inner * 2, height: HUDLayout.planetOrbits.inner * 2)
            Circle().stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 7]))
                .frame(width: HUDLayout.planetOrbits.outer * 2, height: HUDLayout.planetOrbits.outer * 2)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#FFF4D6"), Color(hex: "#FFC24D").opacity(0.6), .clear],
                                     center: .center, startRadius: 0, endRadius: 92))
                .frame(width: 184, height: 184)
                .scaleEffect(1 + 0.04 * sin(model.time * 1.6))
            ForEach(infos) { s in
                let size = s.index < planets.count ? planets[s.index].size : 48
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [s.color.mix(with: .white, by: 0.35), s.color, s.color.mix(with: .black, by: 0.65)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                        .shadow(color: s.on ? s.color : .black.opacity(0.6), radius: s.on ? 18 : 8)
                    SlotGlyph(symbol: s.slot.symbol, size: 17, color: .white)
                }
                .frame(width: size, height: size)
                .opacity(s.on ? 1 : max(model.opacity, 0.45))
                .scaleEffect(s.on ? 1.2 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: s.on)
                .position(s.point)
                SlotLabel(text: s.slot.name, on: s.on, size: 11, width: 110, offColor: Color(hex: "#F0ECE4").opacity(0.72))
                    .position(x: s.point.x, y: s.point.y + size / 2 + 12)
                SlotKeyCap(index: s.index, on: s.on, tint: Color(hex: "#F0ECE4"))
                    .position(x: s.point.x, y: s.point.y + size / 2 + 31)
            }
            VStack(spacing: 2) {
                Text(model.readout.title)
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color(hex: "#3A1C00"))
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(model.readout.app)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "#5C2E00"))
            }
            .minimumScaleFactor(0.7)
            .frame(width: 84, height: 84)
            .background(Circle().fill(RadialGradient(colors: [Color(hex: "#FFF2CC"), Color(hex: "#FFB53D"), Color(hex: "#E0670F")],
                                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 60)))
            .shadow(color: Color(hex: "#FFAA3C").opacity(0.7), radius: 30)
            SettingsGear(model: model, size: 11, tint: Color(hex: "#FFD27A"), litGlyph: Color(hex: "#3A1C00"))
        }
        .opacity(min(1, model.entrance(duration: 0.4) * 1.5))
    }
}
