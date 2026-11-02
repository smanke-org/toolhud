import SwiftUI
import ToolHUDKit

// MARK: - 13 · Liquid Glass

/// Clear glass buttons around a glass hub, laid out like the Orbit. The system glass picks
/// up the wallpaper and follows Light and Dark; only the lit button is tinted, so color
/// always means "this one". With Reduce Transparency on, the glass becomes solid.
struct LiquidGlassView: View {
    let model: HUDModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let mid = HUDModel.middle
        let ink: Color = scheme == .dark ? .white : Color(white: 0.11)
        GlassEffectContainer(spacing: 0) {
            ZStack {
                ForEach(model.infos) { s in
                    let t = model.entrance(delay: Double(s.index) * 0.035, duration: 0.42)
                    let x = mid + (Double(s.point.x) - mid) * t, y = mid + (Double(s.point.y) - mid) * t
                    SlotGlyph(symbol: s.slot.symbol, size: 22, color: s.on ? .white : ink)
                        .frame(width: 64, height: 64)
                        .glassCircle(tint: s.on ? s.color : nil, opacity: model.opacity, solid: reduceTransparency, scheme: scheme)
                        // The glass doesn't redraw for a new tint alone, so it's made anew when
                        // the button lights up or goes out.
                        .id(s.on)
                        .scaleEffect((s.on ? 1.12 : 1) * max(t, 0.2))
                        .hudAnimation(.spring(response: 0.25, dampingFraction: 0.6), value: s.on)
                        .position(x: x, y: y)
                    VStack(spacing: 3) {
                        SlotLabel(text: s.slot.name, on: s.on, size: 11, width: 96, offColor: ink.opacity(0.85), onColor: ink)
                        SlotKeyCap(index: s.index, tint: ink)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassCapsule(opacity: model.opacity, solid: reduceTransparency, scheme: scheme)
                    .position(x: x, y: y + HUDLayout.glassLabelDrop)
                    .opacity(t)
                }
                CenterReadout(model: model, titleFont: .system(size: 13.5, weight: .semibold), detailFont: .system(size: 9),
                              titleColor: ink, detailColor: ink.opacity(0.6), width: 92, keyTint: ink)
                    .frame(width: 112, height: 112)
                    .glassCircle(tint: nil, opacity: model.opacity, solid: reduceTransparency, scheme: scheme)
                SettingsGear(model: model, size: 11, tint: ink, litGlyph: scheme == .dark ? .black : .white)
            }
            .frame(width: HUDLayout.canvas, height: HUDLayout.canvas)
        }
    }
}

extension View {
    /// System glass in a circle, or a solid disc when transparency is reduced.
    @ViewBuilder
    func glassCircle(tint: Color?, opacity: Double, solid: Bool, scheme: ColorScheme) -> some View {
        if solid {
            background(Circle().fill(tint ?? (scheme == .dark ? Color(white: 0.17) : Color(white: 0.96))))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        } else {
            // The tint alone fades on dark wallpapers, so the lit button also gets a rim. No
            // shadow: it renders the glass offscreen and flattens it to plain gray.
            glassEffect(.regular.tint(tint?.opacity(0.55 + 0.4 * opacity)), in: Circle())
                .overlay(Circle().strokeBorder(tint ?? .clear, lineWidth: 2))
        }
    }

    @ViewBuilder
    func glassCapsule(opacity: Double, solid: Bool, scheme: ColorScheme) -> some View {
        if solid {
            background(Capsule().fill(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        } else {
            glassEffect(.regular, in: Capsule())
        }
    }
}
