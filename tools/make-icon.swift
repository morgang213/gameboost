#!/usr/bin/env swift
// Generates GameBoost.icns from scratch using Core Graphics.
// Usage: swift tools/make-icon.swift  →  writes Resources/GameBoost.icns
import Foundation
import AppKit
import CoreGraphics

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("context")
    }

    // Rounded square mask — Apple icon corner radius is ~22.37% of size.
    let radius = s * 0.2237
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Diagonal gradient (purple → pink → orange) — gamer/neon energy.
    let colors = [
        CGColor(red: 0.36, green: 0.20, blue: 0.85, alpha: 1),  // deep purple
        CGColor(red: 0.78, green: 0.18, blue: 0.78, alpha: 1),  // magenta
        CGColor(red: 1.00, green: 0.38, blue: 0.45, alpha: 1),  // pink-coral
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: locations)!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [])

    // Soft inner highlight (top-left glow).
    let glowColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray
    let glow = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0, 1])!
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: s * 0.28, y: s * 0.78),
                           startRadius: 0,
                           endCenter: CGPoint(x: s * 0.28, y: s * 0.78),
                           endRadius: s * 0.55,
                           options: [])

    // Lightning bolt — centered, classic 6-point bolt path.
    // Designed in a 100×100 unit box, then scaled to ~58% of icon.
    let boltScale = s * 0.58 / 100.0
    let originX = (s - 100 * boltScale) / 2
    let originY = (s - 100 * boltScale) / 2

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        // Flip Y so 0 is top in our design coords, but CG origin is bottom-left.
        return CGPoint(x: originX + x * boltScale,
                       y: originY + (100 - y) * boltScale)
    }

    let bolt = CGMutablePath()
    bolt.move(to: p(58, 4))
    bolt.addLine(to: p(20, 56))
    bolt.addLine(to: p(46, 56))
    bolt.addLine(to: p(38, 96))
    bolt.addLine(to: p(80, 40))
    bolt.addLine(to: p(54, 40))
    bolt.closeSubpath()

    // Drop shadow under bolt.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                  blur: s * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(bolt)
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle inner gradient on the bolt for depth.
    ctx.saveGState()
    ctx.addPath(bolt)
    ctx.clip()
    let boltGradColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 1, green: 0.92, blue: 0.88, alpha: 1),
    ] as CFArray
    let boltGrad = CGGradient(colorsSpace: cs, colors: boltGradColors, locations: [0, 1])!
    ctx.drawLinearGradient(boltGrad,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: 0, y: 0),
                           options: [])
    ctx.restoreGState()

    guard let img = ctx.makeImage() else { fatalError("image") }
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

// Write iconset
let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let iconsetURL = URL(fileURLWithPath: cwd).appendingPathComponent("build/GameBoost.iconset")
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for entry in sizes {
    let data = drawIcon(size: entry.px)
    let url = iconsetURL.appendingPathComponent(entry.name)
    try data.write(to: url)
    print("  wrote \(entry.name) (\(entry.px)px)")
}

// Compile to .icns
let resDir = URL(fileURLWithPath: cwd).appendingPathComponent("Resources")
try? fm.createDirectory(at: resDir, withIntermediateDirectories: true)
let icnsURL = resDir.appendingPathComponent("GameBoost.icns")

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("✓ Wrote \(icnsURL.path)")
