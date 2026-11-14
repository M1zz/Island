import CoreText
import SwiftUI

/// One art pixel is this many points on screen.
let px: CGFloat = 2

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

enum Ink {
    static let text: UInt32 = 0x4a2a12
    static let faint: UInt32 = 0x9a7a52
    static let border: UInt32 = 0x5c3a1e
    static let panel: UInt32 = 0xf6e2b3
    static let panelDark: UInt32 = 0xe6c88e
    static let wood: UInt32 = 0x9c6b3a
    static let white: UInt32 = 0xffffff
}

// MARK: - Bitmaps

enum Bitmap {
    /// `pixels` is row-major from the top-left; nil is transparent, otherwise 0xRRGGBB.
    static func image(width: Int, height: Int, pixels: [UInt32?]) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (index, pixel) in pixels.enumerated() {
            guard let pixel else { continue }
            bytes[index * 4] = UInt8(pixel >> 16 & 0xff)
            bytes[index * 4 + 1] = UInt8(pixel >> 8 & 0xff)
            bytes[index * 4 + 2] = UInt8(pixel & 0xff)
            bytes[index * 4 + 3] = 255
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Draws a sprite from rows of palette characters ('.' is transparent).
    static func image(_ rows: [String]) -> CGImage {
        let width = rows.map(\.count).max() ?? 1
        var pixels: [UInt32?] = []
        for row in rows {
            let colors = row.map { Art.palette[$0] }
            pixels += colors + Array(repeating: nil, count: width - colors.count)
        }
        return image(width: width, height: rows.count, pixels: pixels)
    }
}

// MARK: - Text

/// Renders text as crisp pixels: a small system font drawn without antialiasing, then scaled up.
enum PixelFont {
    static let charWidth = 6
    static let lineHeight = 12
    private static let font = CTFontCreateWithName("Monaco" as CFString, 10, nil)
    private static var cache: [String: CGImage] = [:]

    static func wrap(_ text: String, width: Int?) -> [String] {
        guard let width else { return [text] }
        let limit = max(4, width / charWidth)
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ") {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= limit {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        lines.append(line)
        return lines
    }

    static func image(_ text: String, color: UInt32 = Ink.text, outline: UInt32? = nil, wrap: Int? = nil) -> CGImage {
        let key = "\(text)|\(color)|\(outline ?? 1)|\(wrap ?? 0)"
        if let cached = cache[key] { return cached }

        let lines = Self.wrap(text, width: wrap)
        let pad = outline == nil ? 0 : 1
        let width = max(1, (lines.map(\.count).max() ?? 1) * charWidth + pad * 2)
        let height = lines.count * lineHeight + pad * 2
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
        context.setShouldSubpixelPositionFonts(false)

        func draw(_ hex: UInt32, dx: Int, dy: Int) {
            let cgColor = CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
            for (index, line) in lines.enumerated() {
                let string = NSAttributedString(string: line, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor,
                ])
                context.textPosition = CGPoint(x: pad + dx, y: height - pad - 10 - index * lineHeight + dy)
                CTLineDraw(CTLineCreateWithAttributedString(string), context)
            }
        }
        if let outline {
            for dx in -1...1 { for dy in -1...1 where dx != 0 || dy != 0 { draw(outline, dx: dx, dy: dy) } }
        }
        draw(color, dx: 0, dy: 0)

        let image = context.makeImage()!
        cache[key] = image
        return image
    }
}

// MARK: - SwiftUI pieces

struct PixelImage: View {
    let image: CGImage
    var scale: CGFloat = 1

    var body: some View {
        Image(decorative: image, scale: 1)
            .interpolation(.none)
            .resizable()
            .frame(width: CGFloat(image.width) * px * scale, height: CGFloat(image.height) * px * scale)
    }
}

struct PixelText: View {
    let text: String
    var color: UInt32 = Ink.text
    var wrap: Int?
    var scale: CGFloat = 1

    init(_ text: String, color: UInt32 = Ink.text, wrap: Int? = nil, scale: CGFloat = 1) {
        self.text = text
        self.color = color
        self.wrap = wrap
        self.scale = scale
    }

    var body: some View {
        PixelImage(image: PixelFont.image(text, color: color, wrap: wrap), scale: scale)
    }
}

/// A rectangle with one-pixel corners cut off.
struct Notched: Shape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.addRect(CGRect(x: r.minX + px, y: r.minY, width: r.width - px * 2, height: r.height))
        path.addRect(CGRect(x: r.minX, y: r.minY + px, width: r.width, height: r.height - px * 2))
        return path
    }
}

extension View {
    func pixelPanel(face: UInt32 = Ink.panel, border: UInt32 = Ink.border) -> some View {
        background {
            ZStack {
                Notched().fill(Color(hex: border))
                Notched(inset: px).fill(Color(hex: face))
            }
        }
    }
}

struct PixelBar: View {
    let value: Double
    let color: UInt32
    var width: CGFloat = 40
    var height: CGFloat = 6

    var body: some View {
        let inner = width - 2
        let filled = (inner * min(max(value, 0), 1)).rounded()
        ZStack(alignment: .leading) {
            Rectangle().fill(Color(hex: Ink.border))
            Rectangle().fill(Color(hex: 0xfff3d6)).padding(px)
            Rectangle().fill(Color(hex: color))
                .frame(width: filled * px)
                .padding(px)
        }
        .frame(width: width * px, height: height * px)
    }
}
