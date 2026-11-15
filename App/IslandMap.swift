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
    /// The island is ruled into lettered columns and numbered rows, like a chart: "C4".
    static let grid = (columns: 12, rows: 8)

    static func cell(x: Int, y: Int) -> (column: Int, row: Int) {
        (min(max(x * grid.columns / width, 0), grid.columns - 1), min(max(y * grid.rows / height, 0), grid.rows - 1))
    }

    static func cellName(x: Int, y: Int) -> String {
        let cell = cell(x: x, y: y)
        return "\(Character(UnicodeScalar(UInt8(65 + cell.column))))\(cell.row + 1)"
    }

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

        /// Small but in the way: you walk around it, not through it.
        var isSolid: Bool { self == .rock || self == .bush || self == .driftwood }

        /// Picked up whole, so it is gone once gathered. The rest are only stripped.
        var isCarriedOff: Bool { self == .rock || self == .driftwood || self == .shell || self == .fern }

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
        case .beach: (170, 150)
        case .palmGrove: (70, 100)
        case .stream: (278, 122)
        case .jungle: (165, 104)
        case .ridge: (215, 88)
        case .summit: (215, 56)
        }
        return (small.x * scale, small.y * scale)
    }

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

    private static func span(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        let dx = bx - ax, dy = by - ay, length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / length))
        return hypot(px - ax - dx * t, py - ay - dy * t)
    }

    /// The island is drawn on purpose, not rolled: rounded limbs on the sketch, melted together.
    /// A mountain in the north, a peninsula of palms to the west, a river valley to the east,
    /// and a bay in the south where a sandbar runs out to a wreck.
    private static let limbs: [(ax: Double, ay: Double, bx: Double, by: Double, r: Double)] = [
        (215, 58, 215, 58, 46),     // the mountain
        (165, 95, 165, 95, 46),     // the jungle heart
        (130, 82, 130, 82, 34),
        (130, 124, 232, 118, 14),
        (238, 105, 238, 105, 14),
        (218, 104, 218, 104, 14),
        (42, 98, 108, 102, 28),     // the palm peninsula
        (44, 112, 40, 150, 13),     // and its cape
        (95, 128, 125, 150, 14),    // the shore path round to the bay
        (125, 142, 228, 142, 22),   // the south shore
        (135, 150, 122, 184, 11),   // the arms of the bay
        (225, 150, 242, 184, 11),
        (278, 115, 278, 115, 42),   // the river valley
        (288, 152, 288, 152, 28),   // its delta
        (300, 100, 325, 92, 10),    // and the east head
        (170, 160, 170, 196, 7),    // the sandbar
        (170, 196, 170, 196, 12),   // the wreck's islet
    ]

    /// How far inland a spot is, in pixels. Negative is out to sea.
    static func depth(_ x: Int, _ y: Int) -> Double {
        let sx = Double(x) / Double(scale), sy = Double(y) / Double(scale)
        var sum = 0.0
        for limb in limbs { sum += exp((limb.r - span(sx, sy, limb.ax, limb.ay, limb.bx, limb.by)) / 5) }
        let inland = 5 * log(sum)
            + (noise(sx / 20 + 7, sy / 20) - 0.5) * 6
            + (noise(sx / 9 + 40, sy / 9) - 0.5) * 3
            + (noise(sx / 2.5, sy / 2.5 + 90) - 0.5) * 1.2
            + (noise(Double(x) / 14, Double(y) / 14 + 500) - 0.5) * 0.3
        return inland * Double(scale)
    }

    // MARK: Regions, walls and gates

    /// What stands between two regions. You do not wander across: you find the way through.
    enum Wall { case cliff, thicket, rocks }

    /// A way through a wall.
    struct Gate {
        let from, to: Region
        let x, y: Int
        /// Which way it leads, as a unit step.
        let dx, dy: Double
    }

    private static let crown = (x: 215.0, y: 56.0)
    private static let summitRadius = 20.0, ridgeRadius = 44.0
    /// Half a wall's thickness and half a gate's width, on the sketch.
    private static let wallHalf = 0.55, gateHalf = 26.0

    /// The lowlands are rounded territories; whatever they leave over is jungle.
    private static let grove = (x: 55.0, y: 115.0, rx: 68.0, ry: 62.0)
    private static let valley = (x: 295.0, y: 128.0, rx: 62.0, ry: 72.0)
    private static let bay = (x: 170.0, y: 176.0, rx: 92.0, ry: 44.0)

    /// Roughly how far inside a territory a spot is; negative is outside.
    private static func inside(_ land: (x: Double, y: Double, rx: Double, ry: Double), _ wx: Double, _ wy: Double) -> Double {
        (1 - hypot((wx - land.x) / land.rx, (wy - land.y) / land.ry)) * min(land.rx, land.ry)
    }

    /// Which region a spot falls in (land or not), how far the nearest border is on the sketch, and what lies across it.
    private static func survey(_ x: Int, _ y: Int) -> (region: Region, edge: Double, across: Region) {
        let sx = Double(x) / Double(scale), sy = Double(y) / Double(scale)
        let wx = sx + (noise(sx / 16, sy / 16 + 70) - 0.5) * 7
            + (noise(Double(x) / 40, Double(y) / 40 + 300) - 0.5) * 0.6
        let wy = sy + (noise(sx / 16 + 90, sy / 16) - 0.5) * 7
            + (noise(Double(x) / 40 + 300, Double(y) / 40) - 0.5) * 0.6
        // The mountain is not a neat cone.
        let r = hypot(wx - crown.x, wy - crown.y) + (noise(sx / 11 + 5, sy / 11 + 9) - 0.5) * 9
        let inGrove = inside(grove, wx, wy), inValley = inside(valley, wx, wy), inBay = inside(bay, wx, wy)
        let low: Region = inGrove > 0 ? .palmGrove : inValley > 0 ? .stream : inBay > 0 ? .beach : .jungle
        if r < summitRadius { return (.summit, summitRadius - r, .ridge) }
        if r < ridgeRadius {
            return r - summitRadius < ridgeRadius - r ? (.ridge, r - summitRadius, .summit) : (.ridge, ridgeRadius - r, low)
        }
        var best = (region: low, edge: r - ridgeRadius, across: Region.ridge)
        func consider(_ edge: Double, _ across: Region) {
            if edge < best.edge { best = (low, edge, across) }
        }
        switch low {
        case .palmGrove: consider(inGrove, inBay > -3 ? .beach : .jungle)
        case .stream: consider(inValley, inBay > -3 ? .beach : .jungle)
        default:
            consider(-inGrove, .palmGrove)
            consider(-inValley, .stream)
            consider(abs(inBay), low == .beach ? .jungle : .beach)
        }
        return best
    }

    /// Which region a pixel belongs to; nil is sea.
    static func region(x: Int, y: Int) -> Region? {
        guard x >= 0, y >= 0, x < width, y < height, depth(x, y) > 0 else { return nil }
        return survey(x, y).region
    }

    private static func rank(_ region: Region) -> Int { region == .summit ? 2 : region == .ridge ? 1 : 0 }

    /// The ways through, each found by walking across the border from where it was sketched.
    static let gates: [Gate] = [
        gate(.jungle, .beach, 170, 124, 0, 1),          // the locked door behind camp
        gate(.palmGrove, .beach, 100, 148, 1, 0),
        gate(.beach, .stream, 227, 150, 1, 0),
        gate(.palmGrove, .jungle, 110, 108, 1, 0),
        gate(.jungle, .stream, 225, 115, 1, 0),
        gate(.ridge, .jungle, 215 - 34 * 0.94, 56 + 34 * 0.34, -0.94, 0.34),
        gate(.ridge, .stream, 215 + 34 * 0.82, 56 + 34 * 0.57, 0.82, 0.57),   // beside the falls
        gate(.summit, .ridge, 215 + 12 * 0.5, 56 - 12 * 0.87, 0.5, -0.87),    // on the far side of the mountain
    ]

    private static func gate(_ from: Region, _ to: Region, _ sx: Double, _ sy: Double, _ dx: Double, _ dy: Double) -> Gate {
        var last = (x: Int(sx * Double(scale)), y: Int(sy * Double(scale)))
        for step in 1...400 {
            let x = Int((sx + dx * Double(step) * 0.05) * Double(scale)), y = Int((sy + dy * Double(step) * 0.05) * Double(scale))
            if survey(last.x, last.y).region == from, survey(x, y).region == to { return Gate(from: from, to: to, x: x, y: y, dx: dx, dy: dy) }
            last = (x, y)
        }
        fatalError("no border between \(from) and \(to) where the gate was sketched")
    }

    /// The nearest way into a region from land already found.
    static func gate(into region: Region, from known: Set<Region>, near spot: (x: Int, y: Int)) -> (x: Int, y: Int)? {
        gates.filter { ($0.from == region && known.contains($0.to)) || ($0.to == region && known.contains($0.from)) }
            .min { hypot(Double($0.x - spot.x), Double($0.y - spot.y)) < hypot(Double($1.x - spot.x), Double($1.y - spot.y)) }
            .map { ($0.x, $0.y) }
    }

    /// What kind of wall stands on a pixel, if any, and how far up it (-1 foot ... 1 top).
    private static func wall(_ x: Int, _ y: Int, _ spot: (region: Region, edge: Double, across: Region)) -> (kind: Wall, rise: Double)? {
        guard spot.edge < wallHalf else { return nil }
        for gate in gates {
            // A doorway: narrow across, and long enough to pierce the wall wherever it runs thick.
            let ox = Double(x - gate.x), oy = Double(y - gate.y)
            if abs(ox * gate.dx + oy * gate.dy) < 130, abs(ox * gate.dy - oy * gate.dx) < gateHalf { return nil }
        }
        let high = max(rank(spot.region), rank(spot.across))
        let kind: Wall = high > 0 ? .cliff : spot.region == .jungle || spot.across == .jungle ? .thicket : .rocks
        return (kind, (rank(spot.region) == high && high > rank(spot.across) ? spot.edge : -spot.edge) / wallHalf)
    }

    /// Cliffs, thickets and rock spurs: no walking through.
    static func walled(_ x: Int, _ y: Int) -> Bool {
        wall(x, y, survey(x, y)) != nil
    }

    // MARK: Water

    private static let streamSteps = 225 * scale
    private static let streamPoints: [(Double, Double)] = (0...streamSteps).map { step in
        let t = Double(step) / Double(streamSteps)
        return ((233 + 52 * t + 8 * sin(t * 6.5) + 2 * sin(t * 31)) * Double(scale), (74 + 110 * t) * Double(scale))
    }

    /// The pool under the falls, where the river comes off the mountain.
    static let pool: (x: Int, y: Int) = {
        let foot = streamPoints.first { survey(Int($0.0), Int($0.1)).region == .stream } ?? streamPoints[0]
        return (Int(foot.0) + 12, Int(foot.1) + 70)
    }()

    static func streamDistance(_ x: Int, _ y: Int) -> Double {
        // The river runs steadily downhill, so only the stretch level with `y` can be close.
        let first = streamPoints[0].1, last = streamPoints[streamSteps].1
        let middle = Int((Double(y) - first) / (last - first) * Double(streamSteps))
        let nearest = min(max(middle, 0), streamSteps)
        // Far off to the side: no need to measure precisely.
        let aside = abs(Double(x) - streamPoints[nearest].0)
        if aside > 150 { return aside - 75 }
        var best = hypot(Double(x - pool.x), Double(y - pool.y)) - 44
        for index in max(0, nearest - 120)...min(streamSteps, nearest + 120) {
            best = min(best, hypot(Double(x) - streamPoints[index].0, Double(y) - streamPoints[index].1))
        }
        return best
    }

    /// Where the river is at the height of `y`.
    static func riverbank(y: Int) -> (x: Int, y: Int) {
        let first = streamPoints[0].1, last = streamPoints[streamSteps].1
        let step = min(max(Int((Double(y) - first) / (last - first) * Double(streamSteps)), 0), streamSteps)
        return (Int(streamPoints[step].0), Int(streamPoints[step].1))
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
        let d = depth(x, y)
        let speck = Int(hash(x, y) & 0xff)
        func shade(_ base: UInt32, _ dark: UInt32, _ light: UInt32) -> UInt32 {
            speck < 30 ? dark : speck > 236 ? light : base
        }

        guard d > 0, x >= 0, y >= 0, x < width, y < height else {
            if d > -9 { return 0xf2fbf8 }
            if d > -48 { return 0x86bfc6 }
            if d > -130 { return 0x5fa3c0 }
            let dash = y % 5 == 0 && (x + y * 3) % 19 < 4 && speck < 170
            return dash ? 0x4d8cba : 0x3f7fae
        }
        let spot = survey(x, y), region = spot.region
        guard known & bit(region) != 0 else {
            // Chunky on purpose: clouds do not need sharp edges.
            let puff = noise(Double(x / 4) / 5, Double(y / 4) / 3.2 + 200)
            return puff > 0.62 ? 0xd3e3f2 : puff < 0.3 ? 0xffffff : 0xeef5fb
        }

        let rocky = region == .ridge || region == .summit
        let stream = streamDistance(x, y)
        if let wall = wall(x, y, spot) {
            switch wall.kind {
            case .cliff:
                // White water where the river comes over the edge.
                if stream < 26 { return (x + speck / 40) % 3 == 0 ? 0xffffff : 0xbfe6f2 }
                if wall.rise > 0.45 { return shade(0x9a9086, 0x8d827a, 0xb0a69b) }
                if wall.rise < -0.6 { return 0x4a4340 }
                return (y / 3 + Int(hash(x / 9, 0) & 3)) % 3 == 0 ? 0x5e554f : shade(0x6f655e, 0x655c55, 0x7d736b)
            case .thicket:
                let knot = Int(hash(x / 3, y / 3) & 0xff)
                return knot < 20 ? 0x3b2416 : knot < 120 ? 0x1f4a2a : knot > 228 ? 0x487f3f : 0x2c5e34
            case .rocks:
                let lump = Int(hash(x / 7, y / 6) & 0xff)
                return speck < 24 ? 0x4a4340 : lump < 80 ? 0x6f655e : lump > 200 ? 0x8d827a : 0x7d736b
            }
        }
        if stream < 26 { return speck > 240 ? 0xc8f0f4 : stream < 19 ? 0x5fb4e4 : 0x78c4ea }
        if stream < 32 { return rocky ? 0x7d736b : 0xd9c285 }

        if rocky {
            if d < 150 { return shade(0x7d736b, 0x6f655e, 0x8d827a) }
            return region == .ridge
                ? shade(0xa89d90, 0x968b7f, 0xbbb0a4)
                : shade(0xb9afa4, 0xa69c92, 0xcfc6bc)
        }
        if d < 15 { return 0xc9b48a }
        if region == .beach || d < 270 { return shade(0xe3d3ac, 0xd2c097, 0xeee1c0) }
        // Dry scrub where the sand begins.
        if d < 330 { return shade(0xbdb878, 0xaba666, 0xcdc98c) }
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

    /// Things do not grow evenly. Each place on the island is known for something.
    private static let places: [(x: Double, y: Double, r: Double, kind: Kind, chance: Double)] = [
        (170, 196, 12, .driftwood, 0.42),   // the wreck
        (240, 178, 11, .shell, 0.34),       // the tide flats
        (140, 78, 10, .fern, 0.40),         // the fern hollow
        (42, 138, 16, .palm, 0.85),         // coconut point
        (Double(pool.x) / Double(scale), Double(pool.y) / Double(scale) + 3, 5, .rock, 0.36),   // boulders under the falls
    ]

    private static func place(_ x: Int, _ y: Int, tall: Bool) -> (kind: Kind, chance: Double)? {
        let sx = Double(x) / Double(scale), sy = Double(y) / Double(scale)
        return places.first { $0.kind.isTall == tall && hypot(sx - $0.x, sy - $0.y) < $0.r }.map { ($0.kind, $0.chance) }
    }

    private static func isClear(_ x: Int, _ y: Int, tall: Bool) -> Bool {
        guard depth(x, y) > (tall ? 90 : 48), streamDistance(x, y) > (tall ? 52 : 40) else { return false }
        guard survey(x, y).edge > wallHalf + 0.25 else { return false }
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
        // Forest comes in stands with glades between, not as an even sprinkle.
        let stand = noise(Double(x) / 420, Double(y) / 420 + 33)
        let kind: Kind?
        if let place = place(x, y, tall: true) {
            kind = chance < place.chance ? place.kind : nil
        } else {
            switch region {
            case .beach: kind = chance < 0.03 ? .palm : nil
            case .palmGrove: kind = chance < (stand > 0.42 ? 0.5 : 0.08) ? .palm : nil
            case .stream: kind = chance < (stand > 0.55 ? 0.3 : 0.04) ? .tree : chance > 0.95 ? .snag : nil
            case .jungle: kind = chance < (stand > 0.3 ? 0.9 : 0.12) ? .tree : nil
            case .ridge: kind = chance < 0.07 ? .snag : nil
            case .summit: kind = nil
            }
        }
        guard let kind, isClear(x, y, tall: true) else { return nil }
        return Prop(id: .init(tall: true, cellX: cellX, cellY: cellY), kind: kind, x: x, y: y, region: region)
    }

    private static func small(_ cellX: Int, _ cellY: Int) -> Prop? {
        let h = hash(cellX &- 1777, cellY &+ 6007)
        let chance = Double(h >> 16) / 65535
        let x = cellX * smallCell + 4 + Int(h & 0xff) * (smallCell - 8) / 256
        let y = cellY * smallCell + 4 + Int(h >> 8 & 0xff) * (smallCell - 8) / 256
        let place = place(x, y, tall: false)
        // Most ground is bare; say so before doing any real work.
        guard chance < (place?.chance ?? 0.11) else { return nil }
        guard let region = region(x: x, y: y) else { return nil }
        let kind: Kind?
        if let place {
            kind = place.kind
        } else {
            switch region {
            case .beach: kind = chance < 0.012 ? .shell : chance < 0.03 ? .rock : chance < 0.045 ? .driftwood : nil
            case .palmGrove: kind = chance < 0.03 ? .bush : chance < 0.08 ? .fern : chance < 0.09 ? .rock : chance < 0.11 ? .driftwood : nil
            case .stream: kind = chance < 0.03 ? .bush : chance < 0.06 ? .fern : chance < 0.11 ? .rock : nil
            case .jungle: kind = chance < 0.05 ? .bush : chance < 0.11 ? .fern : nil
            case .ridge: kind = chance < 0.10 ? .rock : nil
            case .summit: kind = chance < 0.06 ? .rock : nil
            }
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
