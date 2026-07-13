#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let canvas: CGFloat = 1024

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [red / 255, green / 255, blue / 255, alpha]
    )!
}

private func renderIcon(pixelSize: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    let scale = CGFloat(pixelSize) / canvas
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tile = CGRect(x: 62, y: 62, width: 900, height: 900)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 216, cornerHeight: 216, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 42, color: color(0, 8, 18, 0.55))
    context.addPath(tilePath)
    context.setFillColor(color(4, 22, 39))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let backgroundGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(5, 22, 40), color(8, 48, 73), color(4, 72, 84)] as CFArray,
        locations: [0, 0.58, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: 220, y: 900),
        end: CGPoint(x: 820, y: 110),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let center = CGPoint(x: 512, y: 512)
    let sweepPath = CGMutablePath()
    sweepPath.move(to: center)
    sweepPath.addArc(center: center, radius: 346, startAngle: -.pi / 14, endAngle: .pi / 3.5, clockwise: false)
    sweepPath.closeSubpath()
    context.addPath(sweepPath)
    context.setFillColor(color(42, 236, 205, 0.13))
    context.fillPath()

    context.setLineCap(.round)
    context.setStrokeColor(color(66, 225, 223, 0.44))
    context.setLineWidth(8)
    for radius in [142, 238, 334] as [CGFloat] {
        context.strokeEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    context.setStrokeColor(color(81, 213, 218, 0.28))
    context.setLineWidth(5)
    context.move(to: CGPoint(x: 176, y: center.y))
    context.addLine(to: CGPoint(x: 848, y: center.y))
    context.move(to: CGPoint(x: center.x, y: 176))
    context.addLine(to: CGPoint(x: center.x, y: 848))
    context.strokePath()

    let beamAngle = CGFloat.pi / 4.8
    let beamEnd = CGPoint(
        x: center.x + cos(beamAngle) * 345,
        y: center.y + sin(beamAngle) * 345
    )
    context.setStrokeColor(color(73, 255, 203, 0.92))
    context.setLineWidth(12)
    context.move(to: center)
    context.addLine(to: beamEnd)
    context.strokePath()

    let points: [CGPoint] = [
        CGPoint(x: 334, y: 596),
        CGPoint(x: 424, y: 690),
        CGPoint(x: 548, y: 652),
        CGPoint(x: 673, y: 587),
        CGPoint(x: 622, y: 448),
        CGPoint(x: 503, y: 392),
        CGPoint(x: 374, y: 445),
        center
    ]
    let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 0),
        (0, 7), (1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7)
    ]

    context.setStrokeColor(color(169, 255, 233, 0.78))
    context.setLineWidth(8)
    for edge in edges {
        context.move(to: points[edge.0])
        context.addLine(to: points[edge.1])
    }
    context.strokePath()

    for (index, point) in points.enumerated() {
        let radius: CGFloat = index == points.count - 1 ? 25 : 18
        context.saveGState()
        context.setShadow(offset: .zero, blur: 24, color: color(44, 255, 199, 0.9))
        context.setFillColor(index == points.count - 1 ? color(235, 255, 250) : color(75, 247, 196))
        context.fillEllipse(in: CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        context.restoreGState()
    }

    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(color(126, 239, 225, 0.24))
    context.setLineWidth(5)
    context.strokePath()

    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = repositoryRoot
    .appendingPathComponent("Sources/ShowCodexIQ/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in outputs {
    try writePNG(renderIcon(pixelSize: size), to: outputDirectory.appendingPathComponent(filename))
}

print("Generated \(outputs.count) app icon files in \(outputDirectory.path)")
