import SwiftUI
import ToolHUDKit

// MARK: - 6 · Command Deck

/// A panel of keycaps, each with its app's light, number and shortcut legend.
struct CommandDeckView: View {
    let model: HUDModel
    private static let mint = Color(hex: "#7CF0C5")

    var body: some View {
        let n = model.slots.count
        let cols = HUDLayout.deckColumns(n)
        let rows = Int((Double(n) / Double(cols)).rounded(.up))
        let gridW = Double(cols) * HUDLayout.keySize.width + Double(cols - 1) * HUDLayout.keyGap
        let gridH = Double(rows) * HUDLayout.keySize.height + Double(max(rows - 1, 0)) * HUDLayout.keyGap
        let panelW = max(gridW + 44, 300), panelH = gridH + 44 + 46 + 40
        let open = model.entrance(duration: 0.3)
        ZStack {
            Chamfer(cut: 18, twoCorners: true)
                .fill(Color(hex: "#0E1115").opacity(min(1, model.opacity + 0.05)))
                .overlay(Chamfer(cut: 18, twoCorners: true).stroke(Self.mint.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 16)
                .frame(width: panelW, height: panelH)
            // Header and footer.
            VStack(spacing: 0) {
                HStack {
                    Rectangle().fill(Self.mint).frame(width: 8, height: 8)
                        .opacity(Int(model.time * 1.4) % 2 == 0 ? 1 : 0.25)
                    Text("COMMAND DECK").font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(3)
                        .foregroundStyle(Color(hex: "#E8FFF6"))
                    Spacer()
                    Text("\(String(format: "%02d", n)) KEYS · α \(Int(model.opacity * 100))")
                        .font(.system(size: 9.5, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(Self.mint.opacity(0.7))
                }
                .frame(height: 30)
                Rectangle().fill(Self.mint.opacity(0.18)).frame(height: 1)
                Spacer()
                Rectangle().fill(Self.mint.opacity(0.18)).frame(height: 1)
                HStack {
                    Text(footer).font(.system(size: 10, design: .monospaced)).tracking(0.8)
                        .foregroundStyle(model.focusSlot == nil ? Self.mint.opacity(0.7) : Color(hex: "#E8FFF6"))
                        .lineLimit(1)
                    Spacer()
                    Text("ESC").font(.system(size: 10, design: .monospaced)).foregroundStyle(Self.mint.opacity(0.5))
                }
                .frame(height: 30)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .frame(width: panelW, height: panelH)
            ForEach(model.infos) { s in
                keycap(s)
                    .frame(width: HUDLayout.keySize.width, height: HUDLayout.keySize.height)
                    .position(x: s.point.x, y: s.point.y + 3)
            }
        }
        .offset(y: 14 * (1 - open))
        .scaleEffect(0.96 + 0.04 * open)
        .opacity(min(1, open * 1.3))
    }

    private var footer: String {
        guard let slot = model.focusSlot else { return "› AWAITING INPUT · PRESS 1–\(min(model.slots.count, 9))" }
        if model.fired != nil { return "▶ EXECUTED \(slot.name.uppercased())" }
        return "› \(slot.summary.uppercased())"
    }

    private func keycap(_ s: SlotInfo) -> some View {
        let shortcut: String = {
            if s.slot.mode == .keystroke { return s.slot.keySequence?.display ?? "—" }
            return "↗ " + (s.slot.appName ?? "").uppercased()
        }()
        return ZStack(alignment: .topLeading) {
            Chamfer(cut: 12)
                .fill(LinearGradient(colors: s.on ? [s.color.opacity(s.fired ? 0.75 : 0.42), s.color.opacity(0.16)]
                                                  : [Color(hex: "#282E36").opacity(model.opacity), Color(hex: "#161A1F").opacity(model.opacity)],
                                     startPoint: .top, endPoint: .bottom))
            Chamfer(cut: 12).stroke(s.on ? s.color : Self.mint.opacity(0.16), lineWidth: 1)
            Rectangle().fill(s.color).frame(height: 3).opacity(s.on ? 1 : 0.55)
                .shadow(color: s.color, radius: s.on ? 8 : 3)
                .padding(.leading, 12)
            Text(String(format: "%02d", s.index + 1)).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(hex: "#C8FFEB").opacity(0.55)).padding(.leading, 12).padding(.top, 11)
            SlotGlyph(symbol: s.slot.symbol, size: 18, color: s.on ? .white : s.color)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 11).padding(.top, 9)
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text(s.slot.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "#F0FFF9"))
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text(shortcut).font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(s.on ? .white : Color(hex: "#C8FFEB").opacity(0.6)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.bottom, 9)
        }
        .scaleEffect(s.fired ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: s.on)
    }
}

// MARK: - 7 · Hive

/// Honeycomb cells packed around a center hex that shows what's chosen.
struct HiveView: View {
    let model: HUDModel
    private static let honey = Color(hex: "#FFC94D")

    var body: some View {
        let open = model.entrance(duration: 0.4)
        let cellW = HUDLayout.hexCell.width - 6, cellH = HUDLayout.hexCell.height - 6
        ZStack {
            ForEach(model.infos) { s in
                ZStack {
                    Hexagon().fill(s.on ? s.color : Self.honey.opacity(0.35))
                    Hexagon()
                        .fill(LinearGradient(colors: s.on ? [s.color.opacity(s.fired ? 0.85 : 0.5), Color(hex: "#14100A").opacity(0.95)]
                                                          : [Color(hex: "#2E2618").opacity(model.opacity), Color(hex: "#120F0A").opacity(model.opacity)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(2)
                    VStack(spacing: 5) {
                        SlotGlyph(symbol: s.slot.symbol, size: 20, color: s.on ? .white : s.color)
                        Text(s.slot.name).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: "#FFF7E6"))
                            .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
                            .frame(width: cellW - 16)
                    }
                }
                .frame(width: cellW, height: cellH)
                .shadow(color: s.on ? s.color.opacity(0.7) : .clear, radius: 14)
                .scaleEffect(s.on ? 1.1 : 1)
                .zIndex(s.on ? 1 : 0)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: s.on)
                .position(s.point)
            }
            ZStack {
                Hexagon().fill(Self.honey)
                Hexagon().fill(RadialGradient(colors: [Color(hex: "#2B2112"), Color(hex: "#0F0C07")], center: UnitPoint(x: 0.5, y: 0.35),
                                              startRadius: 0, endRadius: 60))
                    .padding(2)
                VStack(spacing: 4) {
                    SlotGlyph(symbol: model.focusSlot?.symbol ?? "hexagon", size: 24, weight: .medium, color: Self.honey)
                    Text(model.fired != nil ? "SENT" : model.highlighted.map { "SLOT \($0 + 1)" } ?? "HIVE")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Self.honey)
                }
            }
            .frame(width: cellW, height: cellH)
            VStack(spacing: 4) {
                Text(model.readout.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color(hex: "#FFF7E6"))
                Text(model.focusSlot == nil ? "Point at a cell or press its number" : model.readout.detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(model.focusSlot?.tint.color ?? Self.honey.opacity(0.6))
            }
            .lineLimit(1)
            .frame(width: 400)
            .position(x: HUDModel.middle, y: HUDModel.middle + 262)
        }
        .scaleEffect(0.3 + 0.7 * open)
        .rotationEffect(.degrees(-30 * (1 - open)))
        .opacity(min(1, open * 1.4))
    }
}
