import SwiftUI
import ToolHUDKit

/// The HUD as it will open, pad included, scaled to fit, on a made-up wallpaper. Settings
/// shows it at the top of Buttons and Appearance so changes are seen before the HUD is
/// opened. Clicking a button picks it, when `onPick` is set.
struct HUDPreview: View {
    let model: HUDModel
    /// Called with the clicked button's index: the ring's first, then the pad's.
    var onPick: ((Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let box = HUDLayout.previewBounds(look: model.visualization, count: model.slots.count, pad: model.pad)
            let fit = min(geo.size.width / box.width, geo.size.height / box.height, 1)
            let half = HUDLayout.canvas / 2
            ZStack(alignment: .topLeading) {
                HUDDrawing(model: model)
                    .offset(x: -half - box.minX, y: -half - box.minY)
                if model.pad != nil {
                    ButtonPadView(model: model, origin: HUDPoint(box.minX, box.minY))
                }
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .scaleEffect(fit)
            .frame(width: box.width * fit, height: box.height * fit)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onPick else { return }
                let point = HUDPoint(location.x / fit + box.minX, location.y / fit + box.minY)
                if let pad = model.pad, let j = HUDLayout.padButton(at: point, in: pad) {
                    onPick(model.slots.count + j)
                } else if let i = HUDLayout.button(at: point, in: model.visualization, count: model.slots.count,
                                                   dialTurn: Double(model.dialIndex) * 360 / Double(max(model.slots.count, 1)),
                                                   phase: model.phase, pillWidths: model.pillWidths) {
                    onPick(i)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the HUD")
    }
}

/// The wallpaper behind a preview: a calm gradient, dark enough for the dark looks and light
/// enough for the glass ones to show.
struct PreviewBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#34466E"), Color(hex: "#1B1F2E")], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: "#7A5AA8").opacity(0.55), .clear], center: UnitPoint(x: 0.82, y: 0.85),
                           startRadius: 0, endRadius: 260)
        }
    }
}

extension HUDModel {
    /// A preview of these buttons in this look, with `lit` (a ring or pad index) lit.
    @MainActor
    static func settingsPreview(look: Visualization, slots: [Slot], pad: (position: PadPosition, slots: [Slot])?,
                                opacity: Double, lit: Int?) -> HUDModel {
        let model = HUDModel(preview: look, slots: slots, opacity: opacity)
        if let pad {
            model.padPosition = pad.position
            model.padSlots = pad.slots
        }
        model.highlighted = lit
        if look == .dial, let lit, lit < slots.count { model.turnDial(to: lit) }
        return model
    }
}
