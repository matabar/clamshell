#!/usr/bin/env swift
//
// Renders Clamshell.icns: the same glowing ring the widget shows, on a dark
// frosted tile, with a crescent in the middle.
//
//   swift Scripts/make-icon.swift build/Clamshell.icns
//
import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/Clamshell.icns"

let accent = NSColor(red: 0.20, green: 0.84, blue: 0.47, alpha: 1)

/// Draws the icon at 1024×1024 in a normalised coordinate space, then scales.
func drawIcon(in context: CGContext, side: CGFloat) {
    let scale = side / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: the tile is inset from the canvas so the shadow has room.
    let tile = CGRect(x: 92, y: 92, width: 840, height: 840)
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: 188,
        cornerHeight: 188,
        transform: nil
    )

    // Body.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colors = [
        NSColor(red: 0.16, green: 0.18, blue: 0.21, alpha: 1).cgColor,
        NSColor(red: 0.05, green: 0.06, blue: 0.07, alpha: 1).cgColor
    ]
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 512, y: tile.maxY),
            end: CGPoint(x: 512, y: tile.minY),
            options: []
        )
    }
    context.restoreGState()

    // Hairline edge, brighter at the top like a frosted panel.
    context.saveGState()
    context.addPath(tilePath)
    context.setStrokeColor(NSColor(white: 1, alpha: 0.14).cgColor)
    context.setLineWidth(5)
    context.strokePath()
    context.restoreGState()

    // Ring glow: concentric strokes standing in for a blur.
    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 248
    let ringWidth: CGFloat = 58

    for step in stride(from: 7, through: 1, by: -1) {
        let spread = CGFloat(step) * 16
        context.saveGState()
        context.setStrokeColor(accent.withAlphaComponent(0.05).cgColor)
        context.setLineWidth(ringWidth + spread)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        context.strokePath()
        context.restoreGState()
    }

    // The ring itself.
    context.saveGState()
    context.setStrokeColor(accent.cgColor)
    context.setLineWidth(ringWidth)
    context.addArc(
        center: center,
        radius: radius,
        startAngle: 0,
        endAngle: .pi * 2,
        clockwise: false
    )
    context.strokePath()
    context.restoreGState()

    // Crescent: the disc, minus a second disc clipped out of it. Filling both
    // paths even-odd would also paint the bite that falls outside the disc, so
    // the disc becomes a clip and the bite is punched from a covering rect.
    context.saveGState()
    context.addArc(
        center: CGPoint(x: 500, y: 512),
        radius: 140,
        startAngle: 0,
        endAngle: .pi * 2,
        clockwise: false
    )
    context.clip()

    let bite = CGMutablePath()
    bite.addRect(CGRect(x: 320, y: 332, width: 380, height: 380))
    bite.addArc(
        center: CGPoint(x: 575, y: 566),
        radius: 132,
        startAngle: 0,
        endAngle: .pi * 2,
        clockwise: false
    )
    context.addPath(bite)
    context.setFillColor(NSColor(white: 1, alpha: 0.95).cgColor)
    context.fillPath(using: .evenOdd)
    context.restoreGState()
}

func renderPNG(side: Int) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    drawIcon(in: context.cgContext, side: CGFloat(side))
    NSGraphicsContext.restoreGraphicsState()

    return representation.representation(using: .png, properties: [:])
}

// Standard iconset slots, as `iconutil` expects them.
let variants: [(name: String, side: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: output)
let iconset = outputURL.deletingPathExtension().appendingPathExtension("iconset")

do {
    try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    if fileManager.fileExists(atPath: iconset.path) {
        try fileManager.removeItem(at: iconset)
    }
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

    for variant in variants {
        guard let png = renderPNG(side: variant.side) else {
            throw NSError(
                domain: "make-icon",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not render \(variant.name)"]
            )
        }
        try png.write(to: iconset.appendingPathComponent("\(variant.name).png"))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(
            domain: "make-icon",
            code: Int(iconutil.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed"]
        )
    }

    try? fileManager.removeItem(at: iconset)
    print("Wrote \(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
