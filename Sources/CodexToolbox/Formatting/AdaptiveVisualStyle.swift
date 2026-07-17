import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlassCard(
        tint: Color,
        id: String,
        namespace: Namespace.ID
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        if #available(macOS 26.0, *) {
            self
                .overlay {
                    shape.stroke(.white.opacity(0.16), lineWidth: 0.75)
                }
                .glassEffect(.regular.tint(tint.opacity(0.10)).interactive(), in: shape)
                .glassEffectID(id, in: namespace)
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(tint.opacity(0.20), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func adaptiveGlassControlStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func adaptiveGlassIconStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
}
