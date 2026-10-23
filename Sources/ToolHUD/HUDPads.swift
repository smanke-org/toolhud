import SwiftUI
import ToolHUDKit

// MARK: - The button pad

/// One pad button as drawn: its box in the pad view's coordinates, and whether it's lit.
struct PadItem: Identifiable {
    /// Its index among all the HUD's buttons (the ring's come first).
    let index: Int
    /// Its place on the pad, 0 for A.
    let place: Int
    let slot: Slot
    let frame: CGRect
    let on: Bool
    let fired: Bool
    let color: Color
    var key: String { DefaultPad.keyLetters[place] }
    var id: Int { index }
}

/// Extra buttons beside the look, in a tray of the look's own making: a column on the left
/// or right, a row above or below. Every look lays its buttons out in the boxes
/// `HUDLayout.padItems` gives, which is also what the pointer is tested against.
struct ButtonPadView: View {
    let model: HUDModel
    /// The HUD coordinates of this view's top-left corner.
    let origin: HUDPoint

    var body: some View {
        if let pad = model.pad {
            let open = model.entrance(delay: 0.05, duration: 0.3)
            // Slides out from the look as it opens.
            let away = 18 * (1 - open)
            let slide: CGSize = switch pad.position {
            case .left: CGSize(width: away, height: 0)
            case .right: CGSize(width: -away, height: 0)
            case .above: CGSize(width: 0, height: away)
            case .below: CGSize(width: 0, height: -away)
            }
            let items = items(pad)
            ZStack(alignment: .topLeading) {
                PadBackdrop(model: model, pad: pad, items: items, origin: origin)
                ForEach(items) { item in
                    PadCell(model: model, look: pad.look, column: pad.position.isColumn, item: item)
                        .frame(width: item.frame.width, height: item.frame.height)
                        .position(x: item.frame.midX, y: item.frame.midY)
                        .zIndex(item.on ? 1 : 0)
                }
            }
            .offset(slide)
            .opacity(min(1, open * 1.4))
        }
    }

    private func items(_ pad: PadSpec) -> [PadItem] {
        HUDLayout.padItems(pad).enumerated().map { j, box in
            let index = model.slots.count + j
            let slot = model.padSlots[j]
            return PadItem(index: index, place: j, slot: slot,
                           frame: CGRect(x: box.center.x - box.width / 2 - origin.x, y: box.center.y - box.height / 2 - origin.y,
                                         width: box.width, height: box.height),
                           on: model.highlighted == index, fired: model.fired == index, color: slot.tint.color)
        }
    }
}

/// What a look draws behind its pad buttons: the tray, the tie line or the rail.
private struct PadBackdrop: View {
    let model: HUDModel
    let pad: PadSpec
    let items: [PadItem]
    let origin: HUDPoint

    var body: some View {
        let tray = HUDLayout.padTray(pad)
        let rect = CGRect(x: tray.center.x - tray.width / 2 - origin.x, y: tray.center.y - tray.height / 2 - origin.y,
                          width: tray.width, height: tray.height)
        let column = pad.position.isColumn
        ZStack(alignment: .topLeading) {
            if HUDLayout.padStyle(for: pad.look).tether {
                let line = HUDLayout.padTether(pad)
                Path { p in
                    p.move(to: point(line.from))
                    p.addLine(to: point(line.to))
                }
                .stroke(tetherColor, lineWidth: 1)
            }
            switch pad.look {
            case .halo:
                let shape = RoundedRectangle(cornerRadius: column ? 32 : 36, style: .continuous)
                shape.fill(Color(white: 0.07).opacity(model.opacity))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            case .orbit:
                // A dashed orbit line through the buttons.
                rail(lead: 20).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
            case .dial:
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape.fill(Color(hex: "#2A2E37").opacity(model.opacity))
                    .overlay(shape.strokeBorder(Color(hex: "#4A505E"), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                EdgeTicks(edge: pad.position).stroke(Color(hex: "#5B6271"), lineWidth: 1.2)
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            case .stargate:
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill(Color(hex: "#3B3E45").opacity(model.opacity))
                    .overlay(shape.strokeBorder(Color(hex: "#15161A"), lineWidth: 2))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            case .commandDeck:
                let mint = Color(hex: "#7CF0C5")
                Chamfer(cut: 12, twoCorners: true).fill(Color(hex: "#0E1115").opacity(min(1, model.opacity + 0.05)))
                    .overlay(Chamfer(cut: 12, twoCorners: true).stroke(mint.opacity(0.3), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                Text("AUX · \(String(format: "%02d", pad.count))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(mint.opacity(0.85))
                    .position(x: rect.minX + 46, y: rect.minY + 17)
            case .hive:
                EmptyView()
            case .redAlert:
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "#FFB020").opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [14, 6, 2, 6]))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            case .constellation:
                // The stars joined in order, like the ring's.
                Path { p in
                    let stars = items.map { leadCenter($0, lead: 18) }
                    guard let first = stars.first else { return }
                    p.move(to: first)
                    for s in stars.dropFirst() { p.addLine(to: s) }
                }
                .trim(from: 0, to: min(max(model.entrance(delay: 0.15, duration: 0.6), 0), 1))
                .stroke(Color(hex: "#AAC8FF").opacity(0.3), lineWidth: 1)
            case .glassPills:
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                shape.fill(Color.white.opacity(0.45 * model.opacity))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            case .planetary:
                // An outer belt the moons sit on.
                Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private var tetherColor: Color {
        switch pad.look {
        case .dial: Color(hex: "#4A505E")
        case .stargate: Color(hex: "#55585F")
        case .commandDeck: Color(hex: "#7CF0C5").opacity(0.3)
        case .redAlert: Color(hex: "#FF3B4E").opacity(0.5)
        case .glassPills: Color.white.opacity(0.7)
        case .planetary: Color.white.opacity(0.15)
        default: Color.white.opacity(0.25)
        }
    }

    private func point(_ p: HUDPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }

    /// Where a button's round part sits: at the start of a column's box, the top of a row's.
    private func leadCenter(_ item: PadItem, lead: Double) -> CGPoint {
        pad.position.isColumn ? CGPoint(x: item.frame.minX + lead, y: item.frame.midY)
                              : CGPoint(x: item.frame.midX, y: item.frame.minY + lead)
    }

    /// A straight line through every button's round part.
    private func rail(lead: Double) -> Path {
        Path { p in
            guard let first = items.first, let last = items.last else { return }
            p.move(to: leadCenter(first, lead: lead))
            p.addLine(to: leadCenter(last, lead: lead))
        }
    }
}

/// Short tick marks along the side of the Dial's strip that faces the dial.
private struct EdgeTicks: Shape {
    let edge: PadPosition

    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset = 16.0
        switch edge {
        case .right, .left:
            let x = edge == .right ? r.minX + 4 : r.maxX - 4
            for y in stride(from: r.minY + inset, through: r.maxY - inset, by: 5) {
                p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: edge == .right ? x + 5 : x - 5, y: y))
            }
        case .above, .below:
            let y = edge == .below ? r.minY + 4 : r.maxY - 4
            for x in stride(from: r.minX + inset, through: r.maxX - inset, by: 5) {
                p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: edge == .below ? y + 5 : y - 5))
            }
        }
        return p
    }
}

/// A parallelogram leaning right, for Red Alert's blades.
private struct Slant: Shape {
    var lean = 10.0
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addLines([CGPoint(x: r.minX + lean, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.maxX - lean, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)])
        p.closeSubpath()
        return p
    }
}

/// One pad button in a look's style.
private struct PadCell: View {
    let model: HUDModel
    let look: Visualization
    /// In a column (name beside the button) rather than a row (name under it).
    let column: Bool
    let item: PadItem

    var body: some View {
        switch look {
        case .halo: halo
        case .orbit: orbit
        case .dial: dial
        case .stargate: stargate
        case .commandDeck: commandDeck
        case .hive: hive
        case .redAlert: redAlert
        case .constellation: constellation
        case .glassPills: glassPills
        case .planetary: planetary
        }
    }

    private var on: Bool { item.on }

    /// The round part, then the name, then the key: side by side in a column, stacked in a row.
    @ViewBuilder
    private func parts(_ lead: some View, spacing: Double = 10, nameColor: Color, nameFont: Font = .system(size: 12, weight: .medium),
                       uppercase: Bool = false, keyTint: Color = .white) -> some View {
        let name = Text(uppercase ? item.slot.name.uppercased() : item.slot.name)
            .font(nameFont)
            .foregroundStyle(on ? Color.white : nameColor)
            .lineLimit(1).minimumScaleFactor(0.7)
        let key = SlotKeyCap(index: item.index, label: item.key, on: on, tint: keyTint)
        if column {
            HStack(spacing: spacing) {
                lead
                name.frame(maxWidth: .infinity, alignment: .leading)
                key
            }
        } else {
            VStack(spacing: 4) {
                lead
                name.frame(width: item.frame.width - 2)
                key
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Halo: hub coins

    private var halo: some View {
        parts(ZStack {
            Circle().fill(on ? item.color.opacity(min(1, model.opacity * (item.fired ? 0.9 : 0.62)))
                             : Color(white: 0.07).opacity(min(1, model.opacity + 0.12)))
            Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            Circle().strokeBorder(on ? item.color : Color.white.opacity(0.06), lineWidth: 1.5).padding(4)
            SlotGlyph(symbol: item.slot.symbol, size: 16, color: on ? .white : item.color)
        }
        .frame(width: 40, height: 40)
        .shadow(color: on ? item.color.opacity(0.6) : .clear, radius: 14)
        .scaleEffect(item.fired ? 0.94 : on ? 1.1 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: on),
        nameColor: .white.opacity(0.82))
    }

    // MARK: Orbit: satellites

    private var orbit: some View {
        parts(ZStack {
            Circle()
                .fill(on ? item.color.opacity(min(1, model.opacity * 0.75)) : Color(white: 0.12).opacity(model.opacity))
                .overlay(Circle().strokeBorder(on ? item.color : Color.white.opacity(0.15), lineWidth: on ? 1.5 : 1))
                .shadow(color: on ? item.color.opacity(0.5) : .black.opacity(0.45), radius: on ? 14 : 8, y: on ? 0 : 4)
            SlotGlyph(symbol: item.slot.symbol, size: 17, color: on ? .white : item.color)
        }
        .frame(width: 40, height: 40)
        .scaleEffect(on ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: on),
        nameColor: .white.opacity(0.82))
    }

    // MARK: Dial: knobs in a bezel strip

    private var dial: some View {
        let amber = Color(hex: "#FFC56B")
        let pointer = Image(systemName: column ? "arrowtriangle.right.fill" : "arrowtriangle.down.fill")
            .font(.system(size: 9)).foregroundStyle(amber).opacity(on ? 1 : 0)
        let knob = ZStack {
            Circle().fill(Color(hex: "#15181E").opacity(min(1, model.opacity + 0.15)))
            Circle().strokeBorder(on ? amber : Color(hex: "#353A46"), lineWidth: on ? 2 : 1.5)
            SlotGlyph(symbol: item.slot.symbol, size: 16, color: on ? amber : item.color)
        }
        .frame(width: 38, height: 38)
        let lead = Group {
            if column { HStack(spacing: 6) { pointer; knob } } else { VStack(spacing: 2) { pointer; knob } }
        }
        return parts(lead, spacing: 9, nameColor: .white.opacity(0.8), nameFont: .system(size: 11, weight: .semibold),
                     uppercase: true, keyTint: amber)
    }

    // MARK: Stargate: chevrons with lamps

    private var stargate: some View {
        let lamp = Color(hex: "#FF8A1F")
        let lit = on || item.fired
        let chevron = ChevronShape()
            .fill(Color(hex: "#2F3137"))
            .overlay(ChevronShape().stroke(Color(hex: "#0D0E11"), lineWidth: 1.5))
            .overlay(ChevronLamp().fill(item.fired ? Color(hex: "#FFD27A") : lit ? lamp : Color(hex: "#5A2A0E")))
            .shadow(color: lit ? lamp.opacity(0.9) : .clear, radius: 8)
            .frame(width: 22, height: 24)
        let socket = ZStack {
            Circle().fill(lit ? lamp.opacity(0.18) : Color(white: 0.08).opacity(0.85))
                .overlay(Circle().strokeBorder(lit ? lamp : Color(hex: "#34363C"), lineWidth: 1.5))
            SlotGlyph(symbol: item.slot.symbol, size: 15, color: lit ? Color(hex: "#FFD9AD") : item.color)
        }
        .frame(width: 32, height: 32)
        let lead = Group {
            if column { HStack(spacing: 8) { chevron; socket } } else { VStack(spacing: 3) { chevron; socket } }
        }
        return parts(lead, spacing: 8, nameColor: Color(hex: "#FFD9AD").opacity(0.8), keyTint: Color(hex: "#FFD9AD"))
    }

    // MARK: Command Deck: aux keycaps

    private var commandDeck: some View {
        let mint = Color(hex: "#7CF0C5"), legend = Color(hex: "#C8FFEB")
        let name = Text(item.slot.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "#F0FFF9"))
            .lineLimit(1).minimumScaleFactor(0.7)
        return ZStack(alignment: .topLeading) {
            Chamfer(cut: 9)
                .fill(LinearGradient(colors: on ? [item.color.opacity(item.fired ? 0.75 : 0.42), item.color.opacity(0.16)]
                                                : [Color(hex: "#282E36").opacity(model.opacity), Color(hex: "#161A1F").opacity(model.opacity)],
                                     startPoint: .top, endPoint: .bottom))
            Chamfer(cut: 9).stroke(on ? item.color : mint.opacity(0.16), lineWidth: 1)
            Rectangle().fill(item.color).frame(height: 3).opacity(on ? 1 : 0.55)
                .shadow(color: item.color, radius: on ? 8 : 3)
                .padding(.horizontal, 9)
            if column {
                HStack(spacing: 8) {
                    SlotKeyCap(index: item.index, label: item.key, on: on, tint: legend)
                    SlotGlyph(symbol: item.slot.symbol, size: 15, color: on ? .white : item.color)
                    name
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        SlotKeyCap(index: item.index, label: item.key, on: on, tint: legend)
                        Spacer()
                        SlotGlyph(symbol: item.slot.symbol, size: 15, color: on ? .white : item.color)
                    }
                    Spacer(minLength: 0)
                    name.font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 9).padding(.top, 9).padding(.bottom, 7)
            }
        }
        .scaleEffect(item.fired ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: on)
    }

    // MARK: Hive: comb cells

    private var hive: some View {
        let honey = Color(hex: "#FFC94D"), cream = Color(hex: "#FFF7E6")
        return ZStack {
            Hexagon().fill(on ? item.color : honey.opacity(0.35))
            Hexagon()
                .fill(LinearGradient(colors: on ? [item.color.opacity(item.fired ? 0.85 : 0.5), Color(hex: "#14100A").opacity(0.95)]
                                                : [Color(hex: "#2E2618").opacity(model.opacity), Color(hex: "#120F0A").opacity(model.opacity)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(2)
            VStack(spacing: 3) {
                SlotGlyph(symbol: item.slot.symbol, size: 15, color: on ? .white : item.color)
                Text(item.slot.name).font(.system(size: 9, weight: .semibold)).foregroundStyle(cream)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
                    .frame(width: 48)
                SlotKeyCap(index: item.index, label: item.key, on: on, tint: cream)
            }
        }
        .shadow(color: on ? item.color.opacity(0.7) : .clear, radius: 14)
        .scaleEffect(on ? 1.1 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.55), value: on)
    }

    // MARK: Red Alert: blades

    private var redAlert: some View {
        let red = Color(hex: "#FF3B4E"), amber = Color(hex: "#FFB020"), pink = Color(hex: "#FFB3BA")
        let blade = Slant(lean: column ? 10 : 8)
        return ZStack {
            blade.fill(on ? red.opacity(0.32 * max(model.opacity, 0.5) + 0.1) : red.opacity(0.07 + 0.08 * model.opacity))
            if on { HazardStripes().stroke(amber.opacity(0.3), lineWidth: 5).clipShape(blade) }
            blade.stroke(on ? red : red.opacity(0.45), lineWidth: 1.4)
            Group {
                if column {
                    HStack(spacing: 8) {
                        SlotGlyph(symbol: item.slot.symbol, size: 15, color: on ? .white : pink)
                        Text(item.slot.name.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(on ? .white : pink).lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        SlotKeyCap(index: item.index, label: item.key, on: on, tint: pink)
                    }
                    .padding(.leading, 16).padding(.trailing, 18)
                } else {
                    VStack(spacing: 3) {
                        SlotGlyph(symbol: item.slot.symbol, size: 15, color: on ? .white : pink)
                        Text(item.slot.name.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(on ? .white : pink).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: item.frame.width - 22)
                        SlotKeyCap(index: item.index, label: item.key, on: on, tint: pink)
                    }
                }
            }
        }
        .shadow(color: on ? red.opacity(0.8) : .clear, radius: 10)
    }

    // MARK: Constellation: stars

    private var constellation: some View {
        let ice = Color(hex: "#DCE6FF")
        return parts(ZStack {
            Circle()
                .fill(RadialGradient(colors: on ? [item.color.opacity(0.95), item.color.opacity(0.25)]
                                                : [Color(hex: "#1E2640").opacity(model.opacity), Color(hex: "#0C101E").opacity(model.opacity)],
                                     center: .center, startRadius: 0, endRadius: 18))
                .overlay(Circle().strokeBorder(item.color.opacity(on ? 0.9 : 0.45), lineWidth: 1))
                .shadow(color: item.color.opacity(on ? 0.85 : 0.35), radius: on ? 18 : 7)
            SlotGlyph(symbol: item.slot.symbol, size: 15, color: on ? .white : item.color)
        }
        .frame(width: 36, height: 36)
        .scaleEffect(on ? 1.15 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: on),
        nameColor: ice.opacity(0.72), keyTint: ice)
    }

    // MARK: Glass Pills: more pills

    private var glassPills: some View {
        // A row has room for the first word only; the readout gives the whole name.
        let name = column ? item.slot.name : String(item.slot.name.split(separator: " ").first ?? "")
        return HStack(spacing: 7) {
            SlotGlyph(symbol: item.slot.symbol, size: 14, color: on ? .white : item.color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(on ? Color.white.opacity(0.22) : item.color.opacity(0.16)))
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color(hex: "#141821"))
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Text(item.key)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(on ? Color.white : Color(hex: "#4A5060"))
                .frame(minWidth: 18, minHeight: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.white.opacity(0.25) : Color.black.opacity(0.08)))
        }
        .padding(.leading, 5).padding(.trailing, 9)
        .frame(maxHeight: .infinity)
        .background(Capsule().fill(on ? item.color : Color.white.opacity(model.opacity)))
        .overlay(Capsule().strokeBorder(on ? item.color : Color.white.opacity(0.75), lineWidth: 1))
        .shadow(color: on ? item.color.opacity(0.45) : .black.opacity(0.18), radius: on ? 12 : 8, y: 4)
        .scaleEffect(on ? 1.06 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: on)
    }

    // MARK: Planetary: moons

    private var planetary: some View {
        let size = 28 + Double((item.place * 7) % 12)
        let moon = ZStack {
            Circle()
                .fill(RadialGradient(colors: [item.color.mix(with: .white, by: 0.35), item.color, item.color.mix(with: .black, by: 0.65)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                .overlay(Circle().strokeBorder(Color(hex: "#FFF2CC"), lineWidth: on ? 2 : 0))
                .shadow(color: on ? Color(hex: "#FFAA3C").opacity(0.8) : .black.opacity(0.6), radius: on ? 16 : 6)
            SlotGlyph(symbol: item.slot.symbol, size: 14, color: .white)
        }
        .frame(width: size, height: size)
        .opacity(on ? 1 : max(model.opacity, 0.45))
        .scaleEffect(on ? 1.2 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: on)
        .frame(width: 42, height: 42)
        return parts(moon, nameColor: Color(hex: "#F0ECE4").opacity(0.72), keyTint: Color(hex: "#F0ECE4"))
    }
}
