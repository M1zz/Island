// Draws the app icon and writes App/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root: swift Tools/make-icon.swift
import AppKit

// The scene is 52 art pixels square, shown at 16x inside the usual macOS icon margin.
let side = 52
var art = [UInt32](repeating: 0, count: side * side)

func dot(_ x: Int, _ y: Int, _ color: UInt32) {
    if x >= 0, y >= 0, x < side, y < side { art[y * side + x] = color }
}

// A hazy sky over a dark sea: nobody is coming.
let sky: [UInt32] = [0x7f8d94, 0x93a0a3, 0xa9b1ad, 0xc0c1b1, 0xd3ccb2]
for y in 0..<side {
    for x in 0..<side {
        dot(x, y, y < 33 ? sky[min(4, y / 7)] : y < 41 ? 0x40636b : 0x34525b)
    }
}

// A pale sun behind the haze.
for y in 0..<33 {
    for x in 0..<side {
        let far = hypot(Double(x) - 38.5, Double(y) - 14.5)
        if far < 6.2 { dot(x, y, far < 4.6 ? 0xf3ead0 : 0xe2dbc2) }
    }
}

// Swell.
for (x, y, length) in [(3, 35, 5), (40, 36, 6), (9, 46, 6), (36, 48, 7), (22, 50, 4), (45, 43, 4), (1, 41, 3)] {
    for step in 0..<length { dot(x + step, y, 0x6d8f92) }
}

// The islet: foam, wet sand, dry sand.
for y in 33..<side {
    for x in 0..<side {
        let across = (Double(x) - 25.5) / 19, down = (Double(y) - 38.5) / 5.5
        let far = across * across + down * down
        if far < 1.18, y >= 38 { dot(x, y, 0xdfe8e2) }
        if far < 1 { dot(x, y, down > 0.45 ? 0xa3936a : down < -0.35 ? 0xe5d7a6 : 0xd0bd88) }
    }
}

// The palm leans out over everything, far taller than the castaway.
let crown = (x: 27.0, y: 12.0)
for y in 12...37 {
    let rise = Double(37 - y) / 25
    let x = Int((20 + 7 * rise * rise + (rise > 0.8 ? 0.0 : 0.6)).rounded())
    dot(x, y, 0x86592f)
    dot(x + 1, y, y % 4 == 0 ? 0x3b2416 : 0x5c3a1e)
    if y > 34 { dot(x - 1, y, 0x86592f) }
}
for (angle, length, droop) in [(0.25, 15.0, 0.9), (1.05, 10.0, 0.6), (2.1, 10.0, 0.6), (2.95, 15.0, 0.9), (-0.5, 9.0, 1.3), (3.7, 9.0, 1.3)] {
    for step in 0...Int(length * 2) {
        let t = Double(step) / (length * 2)
        let x = Int((crown.x + cos(angle) * length * t).rounded())
        let y = Int((crown.y - sin(angle) * length * t + droop * length * t * t).rounded())
        dot(x, y + 2, 0x1f4a2a)
        dot(x, y + 1, 0x2c5e34)
        dot(x, y, t < 0.75 ? 0x6f9f48 : 0x487f3f)
        if step % 3 == 0, t > 0.25 { dot(x, y + 3, 0x1f4a2a) }
    }
}
for (x, y) in [(26, 14), (28, 15), (29, 13)] {
    dot(x, y, 0x5c3a1e)
    dot(x, y + 1, 0x3b2416)
}

// One castaway, looking out to sea.
let hero: [(Int, Int, UInt32)] = [
    (34, 31, 0x2a1c12), (35, 31, 0x2a1c12),
    (34, 32, 0xd9a877), (35, 32, 0xd9a877),
    (34, 33, 0x3c4444), (35, 33, 0x3c4444), (33, 34, 0xd9a877), (34, 34, 0x3c4444), (35, 34, 0x3c4444), (36, 34, 0xd9a877),
    (34, 35, 0x6b5a44), (35, 35, 0x6b5a44),
    (34, 36, 0xd9a877), (35, 36, 0xd9a877),
    (33, 37, 0x8f8160), (34, 37, 0x8f8160), (35, 37, 0x8f8160), (36, 37, 0x8f8160), (37, 37, 0x8f8160),
]
for (x, y, color) in hero { dot(x, y, color) }

// MARK: Out to files

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func canvas(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let scene = canvas(side)
for y in 0..<side {
    for x in 0..<side {
        let color = art[y * side + x]
        scene.setFillColor(red: CGFloat(color >> 16 & 0xff) / 255, green: CGFloat(color >> 8 & 0xff) / 255,
                           blue: CGFloat(color & 0xff) / 255, alpha: 1)
        scene.fill(CGRect(x: x, y: side - 1 - y, width: 1, height: 1))
    }
}

let master = canvas(1024)
let frame = CGRect(x: 96, y: 96, width: 832, height: 832)
master.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.35))
master.addPath(CGPath(roundedRect: frame, cornerWidth: 186, cornerHeight: 186, transform: nil))
master.setFillColor(gray: 0, alpha: 1)
master.fillPath()
master.setShadow(offset: .zero, blur: 0, color: nil)
master.addPath(CGPath(roundedRect: frame, cornerWidth: 186, cornerHeight: 186, transform: nil))
master.clip()
master.interpolationQuality = .none
master.draw(scene.makeImage()!, in: frame)

let folder = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale, name = "icon_\(size).png"
        let small = canvas(size)
        small.interpolationQuality = .high
        small.draw(master.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
        let png = NSBitmapImageRep(cgImage: small.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: folder.appendingPathComponent(name))
        entries.append(#"    { "idiom" : "mac", "size" : "\#(points)x\#(points)", "scale" : "\#(scale)x", "filename" : "\#(name)" }"#)
    }
}
let contents = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    .write(to: folder.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
