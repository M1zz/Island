import CoreGraphics
import Foundation
import IslandCore

/// The island, described by formulas rather than stored: any spot can be asked what it is,
/// so the world can be far bigger than anything we could keep in memory at once.
/// Coordinates are art pixels, y down.
enum IslandMap {
    /// What fits on screen at once.
    static let viewWidth = 480
    static let viewHeight = 270
    /// The island's outline is designed on a 352 x 212 sketch and blown up this much.
    static let scale = 60
    static let width = 352 * scale
    static let height = 212 * scale
    /// The ground is drawn in square pieces this wide, only around the camera.
    static let chunk = 512

    enum Kind {
        case palm, tree, snag, bush, rock, fern, shell, driftwood

        /// What you get by working on it. A palm is climbed for coconuts, not cut down.
        var item: Item {
            switch self {
            case .palm: .cleanWater
            case .tree, .snag, .driftwood: .wood
            case .bush, .shell: .food
            case .fern: .fiber
            case .rock: .stone
            }
        }

        /// Giants: they block the way and you can walk behind them.
        var isTall: Bool { self == .palm || self == .tree || self == .snag }
    }

    struct Prop {
        /// Which lattice cell grew it; unique across the island.
        struct ID: Hashable {
            let tall: Bool
            let cellX, cellY: Int
        }

        let id: ID
        let kind: Kind
        let x, y: Int
        let region: Region
    }

    /// The middle of each region: where its sign sits on the map.
    static func anchor(_ region: Region) -> (x: Int, y: Int) {
        let small: (x: Int, y: Int) = switch region {
        case .beach: (112, 158)
        case .palmGrove: (72, 104)
        case .stream: (250, 146)
        case .jungle: (168, 100)
        case .ridge: (250, 72)
        case .summit: (188, 54)
        }
        return (small.x * scale, small.y * scale)
    }

    private static let anchors = Region.allCases.map { (region: $0, x: Double(anchor($0).x), y: Double(anchor($0).y)) }

    static let start = (x: anchor(.beach).x, y: anchor(.beach).y + 8)
    static let fire = (x: start.x + 22, y: start.y + 2)
    static let bed = (x: start.x - 24, y: start.y - 8)
    static let signal = (x: anchor(.summit).x + 36, y: anchor(.summit).y + 10)
    /// Foot of the mountain, and how big it stands.
    static let peak = (x: anchor(.summit).x, y: anchor(.summit).y - 14)
    static let mountain = (width: 900, height: 640)

    // MARK: Shape

    private static func hash(_ x: Int, _ y: Int) -> UInt32 {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return h ^ (h >> 16)
    }

    private static func noise(_ x: Double, _ y: Double) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func value(_ x: Int, _ y: Int) -> Double { Double(hash(x, y) & 0xffff) / 65535 }
        let top = value(x0, y0) + (value(x0 + 1, y0) - value(x0, y0)) * sx
        let bottom = value(x0, y0 + 1) + (value(x0 + 1, y0 + 1) - value(x0, y0 + 1)) * sx
        return top + (bottom - top) * sy
    }

    /// Below 1 is land, above is sea.
    static func shore(_ x: Int, _ y: Int) -> Double {
        let sx = Double(x) / Double(scale), sy = Double(y) / Double(scale)
        let dx = (sx - 176) / 150, dy = (sy - 104) / 82
        return sqrt(dx * dx + dy * dy)
            + (noise(sx / 30, sy / 30) - 0.5) * 0.26
            + (noise(sx / 9 + 40, sy / 9) - 0.5) * 0.06
            + (noise(sx / 2.5, sy / 2.5 + 90) - 0.5) * 0.018
            + (noise(Double(x) / 14, Double(y) / 14 + 500) - 0.5) * 0.003
    }

    /// Which region a pixel belongs to; nil is sea.
    static func region(x: Int, y: Int) -> Region? {
        guard x >= 0, y >= 0, x < width, y < height, shore(x, y) < 1 else { return nil }
        let sx = Double(x) / Double(scale), sy = Double(y) / Double(scale)
        let bend = 8.25 * Double(scale)
        let wx = Double(x) + (noise(sx / 16, sy / 16 + 70) - 0.5) * bend
            + (noise(Double(x) / 40, Double(y) / 40 + 300) - 0.5) * 60
            + (noise(Double(x) / 10, Double(y) / 10 + 300) - 0.5) * 8
        let wy = Double(y) + (noise(sx / 16 + 90, sy / 16) - 0.5) * bend
            + (noise(Double(x) / 40 + 300, Double(y) / 40) - 0.5) * 60
            + (noise(Double(x) / 10 + 300, Double(y) / 10) - 0.5) * 8
        return anchors.min { hypot(wx - $0.x, wy - $0.y) < hypot(wx - $1.x, wy - $1.y) }!.region
    }

    private static let streamSteps = 225 * scale
    private static let streamPoints: [(Double, Double)] = (0...streamSteps).map { step in
        let t = Double(step) / Double(streamSteps)
        return ((270 + 22 * t + 8 * sin(t * 6.5) + 2 * sin(t * 31)) * Double(scale), (60 + 114 * t) * Double(scale))
    }

    static func streamDistance(_ x: Int, _ y: Int) -> Double {
        // The river runs steadily downhill, so only the stretch level with `y` can be close.
        let first = streamPoints[0].1, last = streamPoints[streamSteps].1
        let middle = Int((Double(y) - first) / (last - first) * Double(streamSteps))
        let nearest = min(max(middle, 0), streamSteps)
        // Far off to the side: no need to measure precisely.
        let aside = abs(Double(x) - streamPoints[nearest].0)
        if aside > 150 { return aside - 75 }
        var best = Double.infinity
        for index in max(0, nearest - 120)...min(streamSteps, nearest + 120) {
            best = min(best, hypot(Double(x) - streamPoints[index].0, Double(y) - streamPoints[index].1))
        }
        return best
    }

    // MARK: Ground

    /// The regions found so far, packed so that drawing can check them quickly.
    static func mask(_ regions: Set<Region>) -> UInt8 {
        regions.reduce(0) { $0 | bit($1) }
    }

    private static func bit(_ region: Region) -> UInt8 {
        switch region {
        case .beach: 1
        case .palmGrove: 2
        case .stream: 4
        case .jungle: 8
        case .ridge: 16
        case .summit: 32
        }
    }

    /// One square of ground. Land not found yet is drawn as cloud.
    static func terrain(chunkX: Int, chunkY: Int, known: UInt8) -> CGImage {
        Bitmap.image(width: chunk, height: chunk) { x, y in
            color(chunkX * chunk + x, chunkY * chunk + y, known: known)
        }
    }

    private static func color(_ x: Int, _ y: Int, known: UInt8) -> UInt32 {
        let d = shore(x, y)
        let speck = Int(hash(x, y) & 0xff)
        func shade(_ base: UInt32, _ dark: UInt32, _ light: UInt32) -> UInt32 {
            speck < 30 ? dark : speck > 236 ? light : base
        }

        guard let region = region(x: x, y: y) else {
            if d < 1.0015 { return 0xf2fbf8 }
            if d < 1.008 { return 0x86bfc6 }
            if d < 1.022 { return 0x5fa3c0 }
            let dash = y % 5 == 0 && (x + y * 3) % 19 < 4 && speck < 170
            return dash ? 0x4d8cba : 0x3f7fae
        }
        guard known & bit(region) != 0 else {
            // Chunky on purpose: clouds do not need sharp edges.
            let puff = noise(Double(x / 4) / 5, Double(y / 4) / 3.2 + 200)
            return puff > 0.62 ? 0xd3e3f2 : puff < 0.3 ? 0xffffff : 0xeef5fb
        }

        let rocky = region == .ridge || region == .summit
        let stream = streamDistance(x, y)
        if stream < 26 { return speck > 240 ? 0xc8f0f4 : stream < 19 ? 0x5fb4e4 : 0x78c4ea }
        if stream < 32 { return rocky ? 0x7d736b : 0xd9c285 }

        if rocky {
            if d > 0.975 { return shade(0x7d736b, 0x6f655e, 0x8d827a) }
            return region == .ridge
                ? shade(0xa89d90, 0x968b7f, 0xbbb0a4)
                : shade(0xb9afa4, 0xa69c92, 0xcfc6bc)
        }
        if d > 0.9975 { return 0xc9b48a }
        if region == .beach || d > 0.955 { return shade(0xe3d3ac, 0xd2c097, 0xeee1c0) }
        // Dry scrub where the sand begins.
        if d > 0.945 { return shade(0xbdb878, 0xaba666, 0xcdc98c) }
        switch region {
        case .palmGrove: return shade(0xa9ae62, 0x979c55, 0xbcc077)
        case .stream: return shade(0x8fa85a, 0x7f974e, 0xa2b96c)
        default: return shade(0x5f8a4a, 0x527a41, 0x6d9855)
        }
    }

    /// The whole island from high up, one pixel for every `step` on the ground, giants dotted in.
    static func overview(known: UInt8, step: Int) -> CGImage {
        let wide = width / step, tall = height / step
        var pixels = [UInt32?](repeating: nil, count: wide * tall)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let cells = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: tall) { y in
                for x in 0..<wide { cells[y * wide + x] = color(x * step, y * step, known: known) }
            }
        }
        for cellY in 0..<height / giantCell {
            for cellX in 0..<width / giantCell {
                guard let giant = giant(cellX, cellY), known & bit(giant.region) != 0 else { continue }
                let leaf: UInt32 = giant.kind == .snag ? 0x8d827a : 0x2c5e34
                for dy in -2...0 {
                    for dx in -1...1 where giant.x / step + dx >= 0 && giant.x / step + dx < wide && giant.y / step + dy >= 0 {
                        pixels[(giant.y / step + dy) * wide + giant.x / step + dx] = leaf
                    }
                }
            }
        }
        return Bitmap.image(width: wide, height: tall, pixels: pixels)
    }

    // MARK: What grows

    // Everything that grows sits on one of two lattices, at most one thing per cell,
    // decided by hashing the cell. No list of the whole island is ever needed.
    private static let giantCell = 72
    private static let smallCell = 26

    private static func isClear(_ x: Int, _ y: Int, tall: Bool) -> Bool {
        guard shore(x, y) < (tall ? 0.985 : 0.992), streamDistance(x, y) > (tall ? 52 : 40) else { return false }
        for spot in [start, fire, bed, signal] {
            // A giant just south of camp would bury it under its crown.
            if tall, abs(x - spot.x) < 95, y > spot.y - 24, y < spot.y + 175 { return false }
            if hypot(Double(x - spot.x), Double(y - spot.y)) < 18 { return false }
        }
        // Keep the mountain clear.
        return !(abs(x - peak.x) < mountain.width / 2 + 20 && y < peak.y + 6 && y > peak.y - mountain.height - 20)
    }

    private static func giant(_ cellX: Int, _ cellY: Int) -> Prop? {
        let h = hash(cellX &+ 9001, cellY &- 4003)
        let x = cellX * giantCell + 14 + Int(h & 0xff) * (giantCell - 28) / 256
        let y = cellY * giantCell + 14 + Int(h >> 8 & 0xff) * (giantCell - 28) / 256
        let chance = Double(h >> 16) / 65535
        guard let region = region(x: x, y: y) else { return nil }
        let kind: Kind?
        switch region {
        case .beach: kind = chance < 0.05 ? .palm : nil
        case .palmGrove: kind = chance < 0.36 ? .palm : nil
        case .stream: kind = chance < 0.10 ? .tree : chance < 0.15 ? .snag : nil
        case .jungle: kind = chance < 0.78 ? .tree : nil
        case .ridge: kind = chance < 0.07 ? .snag : nil
        case .summit: kind = nil
        }
        guard let kind, isClear(x, y, tall: true) else { return nil }
        return Prop(id: .init(tall: true, cellX: cellX, cellY: cellY), kind: kind, x: x, y: y, region: region)
    }

    private static func small(_ cellX: Int, _ cellY: Int) -> Prop? {
        let h = hash(cellX &- 1777, cellY &+ 6007)
        let chance = Double(h >> 16) / 65535
        // Most ground is bare; say so before doing any real work.
        guard chance < 0.11 else { return nil }
        let x = cellX * smallCell + 4 + Int(h & 0xff) * (smallCell - 8) / 256
        let y = cellY * smallCell + 4 + Int(h >> 8 & 0xff) * (smallCell - 8) / 256
        guard let region = region(x: x, y: y) else { return nil }
        let kind: Kind?
        switch region {
        case .beach: kind = chance < 0.012 ? .shell : chance < 0.03 ? .rock : chance < 0.045 ? .driftwood : nil
        case .palmGrove: kind = chance < 0.03 ? .bush : chance < 0.08 ? .fern : chance < 0.09 ? .rock : chance < 0.11 ? .driftwood : nil
        case .stream: kind = chance < 0.03 ? .bush : chance < 0.06 ? .fern : chance < 0.11 ? .rock : nil
        case .jungle: kind = chance < 0.05 ? .bush : chance < 0.11 ? .fern : nil
        case .ridge: kind = chance < 0.10 ? .rock : nil
        case .summit: kind = chance < 0.06 ? .rock : nil
        }
        guard let kind, isClear(x, y, tall: false) else { return nil }
        for trunk in giants(around: x, y, reach: 16) where hypot(Double(x - trunk.x), Double(y - trunk.y)) < 16 { return nil }
        return Prop(id: .init(tall: false, cellX: cellX, cellY: cellY), kind: kind, x: x, y: y, region: region)
    }

    private static func cells(_ low: Int, _ high: Int, _ size: Int) -> ClosedRange<Int> {
        Int((Double(low) / Double(size)).rounded(.down))...Int((Double(high) / Double(size)).rounded(.down))
    }

    private static func giants(around x: Int, _ y: Int, reach: Int) -> [Prop] {
        var found: [Prop] = []
        for cellY in cells(y - reach, y + reach, giantCell) {
            for cellX in cells(x - reach, x + reach, giantCell) {
                if let giant = giant(cellX, cellY) { found.append(giant) }
            }
        }
        return found
    }

    /// Everything growing within `reach` of a spot (a square, not a circle).
    static func props(around x: Int, _ y: Int, reach: Int) -> [Prop] {
        var found = giants(around: x, y, reach: reach)
        for cellY in cells(y - reach, y + reach, smallCell) {
            for cellX in cells(x - reach, x + reach, smallCell) {
                if let prop = small(cellX, cellY) { found.append(prop) }
            }
        }
        return found
    }

    /// Everything growing on one square of ground.
    static func props(chunkX: Int, chunkY: Int) -> [Prop] {
        let half = chunk / 2
        return props(around: chunkX * chunk + half, chunkY * chunk + half, reach: half).filter {
            $0.x >= chunkX * chunk && $0.x < (chunkX + 1) * chunk && $0.y >= chunkY * chunk && $0.y < (chunkY + 1) * chunk
        }
    }

    /// Whether a giant's trunk stands on this pixel.
    static func blocked(_ x: Int, _ y: Int) -> Bool {
        giants(around: x, y, reach: 12).contains { trunk in
            let dx = Double(x - trunk.x) / 10, dy = Double(y - trunk.y + 3) / 5
            return dx * dx + dy * dy < 1
        }
    }
}
