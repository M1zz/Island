import CoreGraphics
import Foundation
import IslandCore

/// The island, generated once from fixed noise. Coordinates are art pixels, y down.
enum IslandMap {
    /// What fits on screen at once.
    static let viewWidth = 352
    static let viewHeight = 212
    /// The island is this many screens across.
    static let scale = 8
    static let width = viewWidth * scale
    static let height = viewHeight * scale

    enum Prop {
        case palm, tree, bush, rock, fern, shell, flowerPink, flowerWhite

        /// What you get by working on it. Flowers are only pretty.
        var item: Item? {
            switch self {
            case .palm, .tree: .wood
            case .bush, .shell: .food
            case .fern: .fiber
            case .rock: .stone
            case .flowerPink, .flowerWhite: nil
            }
        }
    }

    /// The middle of each region: where its name sits.
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

    static let start = (x: anchor(.beach).x, y: anchor(.beach).y + 8)
    static let fire = (x: start.x + 22, y: start.y + 2)
    static let bed = (x: start.x - 24, y: start.y - 8)
    static let signal = (x: anchor(.summit).x + 36, y: anchor(.summit).y + 10)
    /// Foot of the mountain.
    static let peak = (x: anchor(.summit).x, y: anchor(.summit).y - 14)

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
            + (noise(Double(x) / 8, Double(y) / 8 + 500) - 0.5) * 0.014
    }

    /// Which region every pixel belongs to; nil is sea.
    private static let grid: [Region?] = {
        var grid: [Region?] = []
        grid.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                guard shore(x, y) < 1 else {
                    grid.append(nil)
                    continue
                }
                let sx = Double(x) / Double(scale), sy = Double(y) / Double(scale)
                let wx = Double(x) + (noise(sx / 16, sy / 16 + 70) - 0.5) * 66
                    + (noise(Double(x) / 10, Double(y) / 10 + 300) - 0.5) * 8
                let wy = Double(y) + (noise(sx / 16 + 90, sy / 16) - 0.5) * 66
                    + (noise(Double(x) / 10 + 300, Double(y) / 10) - 0.5) * 8
                grid.append(Region.allCases.min { a, b in
                    hypot(wx - Double(anchor(a).x), wy - Double(anchor(a).y))
                        < hypot(wx - Double(anchor(b).x), wy - Double(anchor(b).y))
                })
            }
        }
        return grid
    }()

    static func region(x: Int, y: Int) -> Region? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return grid[y * width + x]
    }

    private static let streamSteps = 1800
    private static let streamPoints: [(Double, Double)] = (0...streamSteps).map { step in
        let t = Double(step) / Double(streamSteps)
        return ((270 + 22 * t + 8 * sin(t * 6.5) + 2 * sin(t * 31)) * Double(scale), (60 + 114 * t) * Double(scale))
    }

    static func streamDistance(_ x: Int, _ y: Int) -> Double {
        // The stream runs steadily downhill, so only the stretch level with `y` can be close.
        let first = streamPoints[0].1, last = streamPoints[streamSteps].1
        let middle = Int((Double(y) - first) / (last - first) * Double(streamSteps))
        var best = Double.infinity
        let nearest = min(max(middle, 0), streamSteps)
        for index in max(0, nearest - 90)...min(streamSteps, nearest + 90) {
            best = min(best, hypot(Double(x) - streamPoints[index].0, Double(y) - streamPoints[index].1))
        }
        return best
    }

    // MARK: Terrain

    static let terrain: CGImage = {
        var pixels: [UInt32?] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels.append(color(x, y))
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }()

    private static func color(_ x: Int, _ y: Int) -> UInt32 {
        let d = shore(x, y)
        let speck = Int(hash(x, y) & 0xff)
        func shade(_ base: UInt32, _ dark: UInt32, _ light: UInt32) -> UInt32 {
            speck < 30 ? dark : speck > 236 ? light : base
        }

        guard let region = region(x: x, y: y) else {
            if d < 1.004 { return 0xf2fbf8 }
            if d < 1.025 { return 0x8fd8e4 }
            if d < 1.07 { return 0x6cc0de }
            let dash = y % 5 == 0 && (x + y * 3) % 19 < 4 && speck < 170
            return dash ? 0x62b0e0 : 0x4a9bdc
        }

        let rocky = region == .ridge || region == .summit
        let stream = streamDistance(x, y)
        if stream < 9 { return speck > 240 ? 0xc8f0f4 : stream < 6 ? 0x5fb4e4 : 0x78c4ea }
        if stream < 12 { return rocky ? 0x7d736b : 0xd9c285 }

        if rocky {
            if d > 0.93 { return shade(0x7d736b, 0x6f655e, 0x8d827a) }
            return region == .ridge
                ? shade(0xa89d90, 0x968b7f, 0xbbb0a4)
                : shade(0xb9afa4, 0xa69c92, 0xcfc6bc)
        }
        if d > 0.985 { return 0xdcc284 }
        if region == .beach || d > 0.87 { return shade(0xf2dfa2, 0xe6cd88, 0xf9ecbd) }
        // A soft grass rim where the sand begins.
        if d > 0.85 { return shade(0xa9da6a, 0x9aca5c, 0xbce67c) }
        switch region {
        case .palmGrove: return shade(0x9ad45e, 0x86c24f, 0xb0e070)
        case .stream: return shade(0x7fc653, 0x6fb548, 0x96d466)
        default: return shade(0x56a64a, 0x47923f, 0x66b656)
        }
    }

    /// A blanket of cloud over exactly one region, for land not found yet.
    static func fog(over region: Region) -> CGImage { fogs[region]! }

    private static let fogs: [Region: CGImage] = Dictionary(uniqueKeysWithValues: Region.allCases.map { ($0, makeFog(over: $0)) })

    /// Fog is drawn coarser than the land; clouds do not need sharp edges.
    private static let fogStep = 4

    private static func makeFog(over region: Region) -> CGImage {
        var pixels: [UInt32?] = []
        for y in 0..<height / fogStep {
            for x in 0..<width / fogStep {
                guard IslandMap.region(x: x * fogStep + 2, y: y * fogStep + 2) == region else {
                    pixels.append(nil)
                    continue
                }
                let puff = noise(Double(x) / 5, Double(y) / 3.2 + 200)
                pixels.append(puff > 0.62 ? 0xd3e3f2 : puff < 0.3 ? 0xffffff : 0xeef5fb)
            }
        }
        return Bitmap.image(width: width / fogStep, height: height / fogStep, pixels: pixels)
    }

    // MARK: Props

    static let props: [(prop: Prop, x: Int, y: Int, region: Region)] = {
        var seed: UInt64 = 20_261_114
        func roll() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        var placed: [(prop: Prop, x: Int, y: Int, region: Region)] = []
        // Buckets of what is already placed, so spacing checks stay local.
        var buckets: [Int: [Int]] = [:]
        func bucket(_ x: Int, _ y: Int) -> Int { (y / 16) * 1000 + x / 16 }

        func isFree(_ prop: Prop, _ x: Int, _ y: Int) -> Bool {
            guard shore(x, y) < 0.975, streamDistance(x, y) > 20 else { return false }
            for spot in [start, fire, bed, signal] where hypot(Double(x - spot.x), Double(y - spot.y)) < 18 { return false }
            // Keep the mountain clear.
            if abs(x - peak.x) < 30 * scale, y < peak.y + 6, y > peak.y - 42 * scale { return false }
            let small = prop.item == nil
            let spacing: Double = small ? 5 : prop == .tree ? 10 : 12
            for dy in -1...1 {
                for dx in -1...1 {
                    for index in buckets[bucket(x + dx * 16, y + dy * 16)] ?? []
                    where hypot(Double(x - placed[index].x), Double(y - placed[index].y)) < spacing { return false }
                }
            }
            return true
        }
        func add(_ prop: Prop, _ x: Int, _ y: Int, _ region: Region) {
            buckets[bucket(x, y), default: []].append(placed.count)
            placed.append((prop, x, y, region))
        }

        for _ in 0..<150_000 {
            let x = Int(roll() * Double(width)), y = Int(roll() * Double(height))
            let chance = roll()
            guard let region = region(x: x, y: y) else { continue }
            let prop: Prop?
            switch region {
            case .beach:
                prop = chance < 0.05 ? .palm : chance < 0.09 ? .shell : nil
            case .palmGrove:
                prop = chance < 0.45 ? .palm : chance < 0.60 ? .bush : chance < 0.78 ? .fern : chance < 0.9 ? .flowerPink : nil
            case .stream:
                prop = chance < 0.15 ? .tree : chance < 0.33 ? .bush : chance < 0.48 ? .fern
                    : chance < 0.58 ? .rock : chance < 0.8 ? .flowerWhite : nil
            case .jungle:
                prop = chance < 0.65 ? .tree : chance < 0.80 ? .bush : chance < 0.93 ? .fern : nil
            case .ridge:
                prop = chance < 0.40 ? .rock : chance < 0.48 ? .tree : nil
            case .summit:
                prop = chance < 0.30 ? .rock : nil
            }
            guard let prop, isFree(prop, x, y) else { continue }
            add(prop, x, y, region)
        }

        // Every region must really hold what the rules say it yields.
        for region in Region.allCases {
            for item in Item.allCases where region.yields.base(for: item) > 0 {
                let prop: Prop
                switch item {
                case .wood: prop = region == .beach || region == .palmGrove ? .palm : .tree
                case .food: prop = region == .beach ? .shell : .bush
                case .fiber: prop = .fern
                default: prop = .rock
                }
                var have = placed.filter { $0.region == region && $0.prop.item == item }.count
                var tries = 0
                while have < 8, tries < 60_000 {
                    tries += 1
                    let x = Int(roll() * Double(width)), y = Int(roll() * Double(height))
                    guard IslandMap.region(x: x, y: y) == region, isFree(prop, x, y) else { continue }
                    add(prop, x, y, region)
                    have += 1
                }
            }
        }
        return placed
    }()
}
