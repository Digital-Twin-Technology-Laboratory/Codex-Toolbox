import SwiftUI

/// A compact segmented selector that keeps the settings content layer quiet
/// while letting the active segment lift into Liquid Glass on modern macOS.
struct AdaptiveGlassSegmentedPicker<Option, SegmentLabel>: View
where Option: Hashable & Identifiable, SegmentLabel: View {
    private let title: String
    @Binding private var selection: Option
    private let options: [Option]
    private let segmentLabel: (Option) -> SegmentLabel

    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        @ViewBuilder segmentLabel: @escaping (Option) -> SegmentLabel
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.segmentLabel = segmentLabel
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            glassPicker
        } else {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    segmentLabel(option)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @available(macOS 26.0, *)
    private var glassPicker: some View {
        HStack(spacing: 16) {
            Text(title)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(options) { option in
                        segment(option)
                    }
                }
            }
            .padding(2)
            .background(
                Color.secondary.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.separator.opacity(0.22), lineWidth: 0.5)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @available(macOS 26.0, *)
    private func segment(_ option: Option) -> some View {
        let isSelected = selection == option
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return Button {
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.32, dampingFraction: 1)
            ) {
                selection = option
            }
        } label: {
            segmentLabel(option)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .padding(.horizontal, 7)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Color.clear
                    .glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID("selected-segment", in: glassNamespace)
            }
        }
        .accessibilityValue(isSelected ? "已选择" : "")
    }
}
