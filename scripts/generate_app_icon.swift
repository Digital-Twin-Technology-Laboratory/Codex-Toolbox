#!/usr/bin/env -S xcrun swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private func loadPNG(at url: URL) throws -> CGImage {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw CocoaError(.fileReadCorruptFile)
    }

    return image
}

private func resize(_ image: CGImage, to pixelSize: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.coderInvalidValue)
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    guard let resizedImage = context.makeImage() else {
        throw CocoaError(.coderInvalidValue)
    }

    return resizedImage
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
let sourceURL = repositoryRoot
    .appendingPathComponent("design/icon-concepts/codex-radar-terminal-b.svg")
let masterURL = repositoryRoot
    .appendingPathComponent("design/icon-composer/ShowCodexIQ-legacy-1024.png")
let previewURL = repositoryRoot
    .appendingPathComponent("design/icon-concepts/codex-radar-terminal-b-preview.png")
let outputDirectory = repositoryRoot
    .appendingPathComponent("design/icon-composer/ShowCodexIQLegacy.iconset", isDirectory: true)

let renderer = Process()
renderer.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
renderer.arguments = [
    "-s", "format", "png",
    sourceURL.path,
    "--out", masterURL.path
]
try renderer.run()
renderer.waitUntilExit()
guard renderer.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

try Data(contentsOf: masterURL).write(to: previewURL, options: .atomic)

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

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

let sourceImage = try loadPNG(at: masterURL)
for (filename, size) in outputs {
    let image = try resize(sourceImage, to: size)
    try writePNG(image, to: outputDirectory.appendingPathComponent(filename))
}

print("Generated full-bleed master and \(outputs.count) legacy app icon files from \(sourceURL.lastPathComponent)")
