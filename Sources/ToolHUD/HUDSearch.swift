import SwiftUI
import ToolHUDKit

/// The search card over the HUD: what's been typed, and the best matches below it.
/// Positions come from `SearchCardLayout`, which the controller also uses for clicks.
struct SearchCardView: View {
    let model: HUDModel
    /// Where the HUD's center is in the parent's coordinates.
    let center: CGPoint

    private var rows: Int { max(model.results.count, 1) }

    var body: some View {
        let origin = SearchCardLayout.origin(rows: rows)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 1) {
                    Text(model.query.isEmpty ? "Search buttons, apps and menus" : model.query)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(model.query.isEmpty ? 0.45 : 1))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(1)
                    // A caret that blinks on the HUD's own clock.
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                        .opacity(Int(model.time * 2) % 2 == 0 ? 1 : 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: SearchCardLayout.fieldHeight)
            Divider().overlay(Color.white.opacity(0.15))
            if model.results.isEmpty {
                Text("No matches")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: SearchCardLayout.rowHeight)
            } else {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { i, result in
                    row(result, selected: i == model.resultIndex)
                }
            }
            Text("↩ run   ↑↓ choose   esc back")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .frame(height: SearchCardLayout.footerHeight)
        }
        .frame(width: SearchCardLayout.width, height: SearchCardLayout.height(rows: rows), alignment: .top)
        .background(Color(red: 0.09, green: 0.1, blue: 0.12).opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .offset(x: center.x + origin.x, y: center.y + origin.y)
    }

    private func row(_ result: SearchResult, selected: Bool) -> some View {
        HStack(spacing: 10) {
            SlotGlyph(symbol: result.symbol, size: 13, color: selected ? .white : result.color.color)
                .frame(width: 26, height: 26)
                .background((selected ? Color.white : result.color.color).opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(result.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            Text(result.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(selected ? 0.85 : 0.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 130, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: SearchCardLayout.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.85) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 4)
    }
}

/// A small green light beside each button whose feature is on, as its app reports it.
struct StateLightsView: View {
    let model: HUDModel
    let center: CGPoint
    @State private var states = FeatureStates.shared

    var body: some View {
        // Up and to the right of a ring button's icon; in the top-right corner of a wide
        // pad row, where the label would otherwise run under it.
        let ring = model.centers.map { HUDPoint($0.x + 15, $0.y - 17) }
        let padItems = model.pad.map { HUDLayout.padItems($0) } ?? []
        let padSpots: [HUDPoint] = padItems.map(Self.lightSpot)
        let points: [(Int, HUDPoint)] = model.slots.indices.compactMap { i in
            states.isOn(model.slots[i]) == true && i < ring.count ? (i, ring[i]) : nil
        } + model.padSlots.indices.compactMap { j in
            states.isOn(model.padSlots[j]) == true && j < padSpots.count ? (model.slots.count + j, padSpots[j]) : nil
        }
        ZStack(alignment: .topLeading) {
            ForEach(points, id: \.0) { _, p in
                Circle()
                    .fill(Color(red: 0.25, green: 0.95, blue: 0.45))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                    .shadow(color: Color(red: 0.25, green: 0.95, blue: 0.45).opacity(0.9), radius: 5)
                    .offset(x: center.x + p.x - 5, y: center.y + p.y - 5)
            }
        }
        .opacity(model.entrance(delay: 0.12))
        .allowsHitTesting(false)
    }

    private static func lightSpot(_ item: (center: HUDPoint, width: Double, height: Double)) -> HUDPoint {
        let c = item.center
        if item.width > item.height * 1.4 {
            return HUDPoint(c.x + item.width / 2 - 11, c.y - item.height / 2 + 11)
        }
        return HUDPoint(c.x + 15, c.y - 17)
    }
}
