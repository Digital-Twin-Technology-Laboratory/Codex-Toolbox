import SwiftUI

struct WeightDistributionSlider: View {
    let firstBoundary: Int
    let secondBoundary: Int
    let onFirstBoundaryChange: (Int) -> Void
    let onSecondBoundaryChange: (Int) -> Void

    @State private var activeDivider: Divider?

    private let thumbDiameter: CGFloat = 18
    private let trackHeight: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - thumbDiameter, 1)
            let firstX = xPosition(for: firstBoundary, usableWidth: usableWidth)
            let secondX = xPosition(for: secondBoundary, usableWidth: usableWidth)

            ZStack {
                distributionTrack(width: usableWidth)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                dividerThumb(color: .blue, isActive: activeDivider == .first)
                    .position(x: firstX, y: geometry.size.height / 2)
                    .accessibilityLabel("智商与费用分隔点")
                    .accessibilityValue("智商 \(firstBoundary)%")
                    .accessibilityAdjustableAction { direction in
                        adjust(.first, direction: direction)
                    }

                dividerThumb(color: .green, isActive: activeDivider == .second)
                    .position(x: secondX, y: geometry.size.height / 2)
                    .accessibilityLabel("费用与耗时分隔点")
                    .accessibilityValue("费用与智商合计 \(secondBoundary)%")
                    .accessibilityAdjustableAction { direction in
                        adjust(.second, direction: direction)
                    }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(usableWidth: usableWidth))
        }
        .frame(height: 34)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("综合排名权重")
    }

    private func distributionTrack(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.blue
                .frame(width: width * CGFloat(firstBoundary) / 100)
            Color.green
                .frame(width: width * CGFloat(secondBoundary - firstBoundary) / 100)
            Color.orange
                .frame(width: width * CGFloat(100 - secondBoundary) / 100)
        }
        .frame(width: width, height: trackHeight)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
        }
    }

    private func dividerThumb(color: Color, isActive: Bool) -> some View {
        Circle()
            .fill(.background)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .overlay {
                Circle()
                    .stroke(color, lineWidth: isActive ? 3 : 2)
            }
            .shadow(color: .black.opacity(isActive ? 0.22 : 0.14), radius: isActive ? 3 : 2, y: 1)
            .scaleEffect(isActive ? 1.08 : 1)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private func xPosition(for value: Int, usableWidth: CGFloat) -> CGFloat {
        thumbDiameter / 2 + usableWidth * CGFloat(value) / 100
    }

    private func dragGesture(usableWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let rawValue = (value.location.x - thumbDiameter / 2) / usableWidth * 100
                let percentage = min(max(Int(rawValue.rounded()), 0), 100)

                if activeDivider == nil {
                    let firstDistance = abs(percentage - firstBoundary)
                    let secondDistance = abs(percentage - secondBoundary)
                    if firstDistance == secondDistance {
                        guard value.translation.width != 0 else { return }
                        activeDivider = value.translation.width < 0 ? .first : .second
                    } else {
                        activeDivider = firstDistance < secondDistance ? .first : .second
                    }
                }

                switch activeDivider {
                case .first:
                    onFirstBoundaryChange(min(percentage, secondBoundary))
                case .second:
                    onSecondBoundaryChange(max(percentage, firstBoundary))
                case nil:
                    break
                }
            }
            .onEnded { _ in
                activeDivider = nil
            }
    }

    private func adjust(_ divider: Divider, direction: AccessibilityAdjustmentDirection) {
        switch (divider, direction) {
        case (.first, .increment):
            onFirstBoundaryChange(min(firstBoundary + 1, secondBoundary))
        case (.first, .decrement):
            onFirstBoundaryChange(max(firstBoundary - 1, 0))
        case (.second, .increment):
            onSecondBoundaryChange(min(secondBoundary + 1, 100))
        case (.second, .decrement):
            onSecondBoundaryChange(max(secondBoundary - 1, firstBoundary))
        @unknown default:
            break
        }
    }

    private enum Divider {
        case first
        case second
    }
}
