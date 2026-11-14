import CoreGraphics
import Foundation
import IslandCore

/// Every sprite in the game, drawn by hand as rows of palette characters.
enum Art {
    static let palette: [Character: UInt32] = [
        "k": 0x3b2416, "w": 0xffffff, "s": 0xf6c79a, "h": 0x7a4a22,
        "r": 0xe0564c, "R": 0xa83a35, "b": 0x4a78c2, "B": 0x35568f,
        "y": 0xf9d65c, "o": 0xf08a3c, "g": 0x5fae3f, "G": 0x3c7f35,
        "l": 0x9bd65c, "t": 0x9c6b3a, "T": 0x5c3a1e, "n": 0xd9a865,
        "N": 0xf6e2b3, "c": 0x9a8f85, "C": 0x6f655e, "v": 0xc9c0b6,
        "a": 0x9fe0ea, "A": 0x4a9bdc, "p": 0xf29bb0, "e": 0xedc96c,
        "E": 0xc9a046, "d": 0x2f6a30, "x": 0xd8e8f5,
    ]

    // MARK: Castaway

    private static let heroTop = [
        "...kkkkkk...",
        "..keeeeeek..",
        ".keeeeeeeek.",
        "kEEEEEEEEEEk",
        ".khhsssshhk.",
        ".kskssssksk.",
        ".kspsssspsk.",
        "..kssssssk..",
        ".kkrrrrrrkk.",
        "ksrrrwwrrrsk",
        "kskrrrrrrksk",
        ".kkbbbbbbkk.",
    ]
    static let heroIdle = Bitmap.image(heroTop + [
        "..kbbkkbbk..",
        "..ksk..ksk..",
        "..kkk..kkk..",
    ])
    static let heroStepA = Bitmap.image(heroTop + [
        "..kbbkkbbk..",
        "..ksk..kkk..",
        "..kkk.......",
    ])
    static let heroStepB = Bitmap.image(heroTop + [
        "..kbbkkbbk..",
        "..kkk..ksk..",
        ".......kkk..",
    ])
    // Seen from the side, facing right; flipped for left.
    private static let heroSideHead = [
        "...kkkkkk...",
        "..keeeeeek..",
        ".keeeeeeeek.",
        ".kEEEEEEEEEk",
        ".khhhhssssk.",
        ".khhhsssksk.",
        ".khhsssspsk.",
        "..khsssssk..",
    ]
    static let heroSideIdle = Bitmap.image(heroSideHead + [
        "...krrrrk...",
        "..krrrsrk...",
        "..krrrsrk...",
        "...kbbbbk...",
        "...kbbbk....",
        "...kskk.....",
        "...kkkk.....",
    ])
    /// Legs apart, front arm swung forward.
    static let heroSideStepA = Bitmap.image(heroSideHead + [
        "...krrrrk...",
        "..krrrrrsk..",
        "..krrrrrkk..",
        "...kbbbbk...",
        "..kbbkkbbk..",
        ".ksk...ksk..",
        ".kkk...kkkk.",
    ])
    /// Legs passing, arm swung back.
    static let heroSideStepB = Bitmap.image(heroSideHead + [
        "...krrrrk...",
        "..ksrrrrk...",
        "..kkrrrrk...",
        "...kbbbbk...",
        "...kbbbk....",
        "....ksk.....",
        "....kkkk....",
    ])
    static let heroAsleep = Bitmap.image([
        "....kkkkkkkkkkk.",
        ".kkkeeekrrrrrbbk",
        "kEeeesskrrrrrbbk",
        ".kkkeeekrrrrrbbk",
        "....kkkkkkkkkkk.",
    ])

    // MARK: Plants and rocks


    // MARK: Giant trees

    /// The trees here dwarf a castaway, so they are grown from a recipe instead of drawn by hand.
    static let trees = (0..<3).map(makeTree)
    static let palms = (0..<3).map(makePalm)

    private static func speck(_ x: Int, _ y: Int, _ salt: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ salt &* 2_246_822_519)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Int((h ^ (h >> 16)) & 0xff)
    }

    private static let leaves: [UInt32] = [0x2c5e34, 0x487f3f, 0x6f9f48, 0xa3c462]
    private static let leafEdge: UInt32 = 0x1f4a2a
    private static let bark: [UInt32] = [0x5c3a1e, 0x86592f, 0xa87a48]

    private static func makeTree(_ variant: Int) -> CGImage {
        let width = 132, height = 150, middle = width / 2
        var pixels = [UInt32?](repeating: nil, count: width * height)

        // Trunk, flaring into roots.
        for y in 80..<height - 1 {
            let flare = max(0, y - (height - 24))
            let half = 9 + flare * flare / 30
            let center = middle + Int((sin(Double(y) / 21 + Double(variant) * 2) * 2).rounded())
            for x in center - half...center + half {
                let across = Double(x - center + half) / Double(half * 2)
                var tone = across < 0.3 ? 2 : across < 0.68 ? 1 : 0
                if speck(x, y / 7, variant) < 44 { tone = max(0, tone - 1) }
                if y < 104 { tone = max(0, tone - 1) }
                let edge = x == center - half || x == center + half || y == height - 2
                pixels[y * width + x] = edge ? 0x3b2416 : bark[tone]
            }
        }

        // Canopy: overlapping clumps, each lit from the upper left.
        var clumps: [(x: Double, y: Double, r: Double)] = (0..<17).map { index in
            let angle = Double(index) * 2.4 + Double(variant) * 1.3
            let reach = (Double(index) + 0.5) / 17
            return (Double(middle) + cos(angle) * sqrt(reach) * 41, 54 + sin(angle) * sqrt(reach) * 29,
                    16 + Double(speck(index, variant, 7) % 8))
        }
        clumps.sort { $0.y < $1.y }
        var owner = [Int?](repeating: nil, count: width * height)
        for (index, clump) in clumps.enumerated() {
            for y in max(0, Int(clump.y - clump.r) - 2)...min(height - 1, Int(clump.y + clump.r) + 2) {
                for x in max(0, Int(clump.x - clump.r) - 2)...min(width - 1, Int(clump.x + clump.r) + 2) {
                    let ragged = Double(speck(x / 3, y / 3, index) % 3) - 1
                    if hypot(Double(x) - clump.x, Double(y) - clump.y) < clump.r + ragged { owner[y * width + x] = index }
                }
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                guard let index = owner[y * width + x] else { continue }
                let rim = x == 0 || y == 0 || x == width - 1 || owner[y * width + x - 1] == nil
                    || owner[y * width + x + 1] == nil || owner[(y - 1) * width + x] == nil || owner[(y + 1) * width + x] == nil
                let clump = clumps[index]
                var light = ((Double(x) - clump.x) * -0.55 + (Double(y) - clump.y) * -0.83) / clump.r
                light += Double(speck(x, y, variant)) / 255 * 0.36 - 0.18
                light -= (Double(y) - 54) / 29 * 0.22
                pixels[y * width + x] = rim ? leafEdge : leaves[light > 0.5 ? 3 : light > 0.02 ? 2 : light > -0.5 ? 1 : 0]
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }

    private static func makePalm(_ variant: Int) -> CGImage {
        let width = 170, height = 150
        var pixels = [UInt32?](repeating: nil, count: width * height)
        func put(_ x: Int, _ y: Int, _ color: UInt32) {
            if x >= 0, y >= 0, x < width, y < height { pixels[y * width + x] = color }
        }
        let foot = (x: Double(width / 2), y: Double(height - 2))
        let crown = (x: Double(width / 2 + 6 + variant * 3), y: 48.0)

        // A bowed, ringed trunk.
        for step in 0...400 {
            let along = Double(step) / 400
            let x = foot.x + (crown.x - foot.x) * along - sin(along * .pi) * 9
            let y = Int(foot.y + (crown.y - foot.y) * along)
            let half = Int((6.5 - 2.5 * along + max(0, 1 - along * 10) * 4).rounded())
            for dx in -half...half {
                let across = Double(dx + half) / Double(half * 2)
                let tone = y % 7 == 0 ? 0 : across < 0.35 ? 2 : across < 0.7 ? 1 : 0
                put(Int(x) + dx, y, abs(dx) == half || step == 0 ? 0x3b2416 : [0x7a5230, 0xa87a48, 0xc9a26b][tone])
            }
        }

        // Fronds: a rib that arcs out and droops, with leaflets hanging from it.
        for degrees in [112.0, 68, 140, 40, 170, 10, 205, -12] {
            let angle = (degrees + Double(variant) * 5) * .pi / 180
            let length = 62 + Double(speck(Int(degrees), variant, 3) % 12)
            for step in 0..<Int(length * 3) {
                let along = Double(step) / (length * 3)
                let x = Int(crown.x + cos(angle) * length * along)
                let y = Int(crown.y - sin(angle) * length * along + 30 * along * along)
                var hang = Int(3 + 14 * pow(sin(.pi * min(1, along * 1.08)), 0.7))
                if (x + variant) % 5 == 0 { hang -= 4 }
                put(x, y - 2, leafEdge)
                put(x, y - 1, leaves[3])
                for drop in 0...max(0, hang) {
                    put(x, y + drop, drop == hang ? leafEdge : leaves[drop * 3 < hang ? 2 : drop * 3 < hang * 2 ? 1 : 0])
                }
            }
        }

        for nut in [(-5, 6), (4, 7), (-1, 11)] {
            for dy in -4...4 {
                for dx in -4...4 where dx * dx + dy * dy <= 16 {
                    put(Int(crown.x) + nut.0 + dx, Int(crown.y) + nut.1 + dy,
                        dx * dx + dy * dy > 9 ? 0x3b2416 : dx < 0 && dy < 0 ? 0xa87a48 : 0x7a4a22)
                }
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }

    /// A dead giant, bleached by salt and sun.
    static let snags = (0..<2).map(makeSnag)

    private static func makeSnag(_ variant: Int) -> CGImage {
        let width = 96, height = 124, middle = width / 2
        var solid = [Bool](repeating: false, count: width * height)
        func limb(from: (Double, Double), to: (Double, Double), thick: Double, thin: Double) {
            let steps = Int(hypot(to.0 - from.0, to.1 - from.1) * 2)
            for step in 0...steps {
                let along = Double(step) / Double(steps), radius = thick + (thin - thick) * along
                let cx = from.0 + (to.0 - from.0) * along + sin(along * 5 + Double(variant)) * 1.5
                let cy = from.1 + (to.1 - from.1) * along
                for y in Int(cy - radius)...Int(cy + radius) {
                    for x in Int(cx - radius)...Int(cx + radius)
                    where x >= 0 && y >= 0 && x < width && y < height && hypot(Double(x) - cx, Double(y) - cy) <= radius {
                        solid[y * width + x] = true
                    }
                }
            }
        }
        let foot = (Double(middle), Double(height - 3)), top = (Double(middle + 6 - variant * 10), 14.0)
        limb(from: foot, to: top, thick: 9, thin: 2)
        limb(from: (foot.0 - 8, foot.1), to: (foot.0 + 8, foot.1), thick: 4, thin: 4)
        for (index, reach) in [(-34.0, -30.0), (30, -34), (-24, -22), (26, -16), (-14, -26)].enumerated() {
            let along = 0.38 + Double(index) * 0.12
            let start = (foot.0 + (top.0 - foot.0) * along, foot.1 + (top.1 - foot.1) * along)
            limb(from: start, to: (start.0 + reach.0, start.1 + reach.1), thick: 4.5 - Double(index) * 0.5, thin: 1)
        }
        func isSolid(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && solid[y * width + x] }
        var pixels = [UInt32?](repeating: nil, count: width * height)
        for y in 0..<height {
            for x in 0..<width where solid[y * width + x] {
                let rim = !isSolid(x - 1, y) || !isSolid(x + 1, y) || !isSolid(x, y - 1) || !isSolid(x, y + 1)
                let lit = !isSolid(x - 3, y - 1), dark = !isSolid(x + 3, y + 1) || speck(x, y / 6, variant) < 36
                pixels[y * width + x] = rim ? 0x3b3430 : lit ? 0xd6cec4 : dark ? 0x7d736b : 0xa89d92
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }

    /// The pool of shade under a giant tree.
    static let shade: CGImage = {
        let width = 72, height = 22
        var pixels: [UInt32?] = []
        for y in 0..<height {
            for x in 0..<width {
                let dx = (Double(x) - 35.5) / 36, dy = (Double(y) - 10.5) / 11
                pixels.append(dx * dx + dy * dy < 1 ? 0x10301c : nil)
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }()

    static let bush = Bitmap.image([
        "..dddd...",
        ".dglggd..",
        "dglgggGd.",
        "dgggggGGd",
        ".dGGGGGd.",
    ])
    static let rock = Bitmap.image([
        "..CCCC...",
        ".CvvvcC..",
        "CvvvccCC.",
        "CvvcccCCC",
        ".CCCCCCC.",
    ])
    static let fern = Bitmap.image([
        "l..l..l",
        ".l.l.l.",
        ".lglgl.",
        "..ggg..",
        "..GgG..",
    ])
    static let bedroll = Bitmap.image([
        ".kkkkkkkkkkkk.",
        "kNNkrrrrrrrrRk",
        "kNNkrwrrrwrrRk",
        "kNNkrrrrrrrrRk",
        ".kkkkkkkkkkkk.",
    ])
    static let cairn = Bitmap.image([
        "....CC....",
        "...CvcC...",
        "..CCvvCC..",
        ".CvcCCvcC.",
        "CvvcCvvccC",
        ".CCCCCCCC.",
    ])
    static let shell = Bitmap.image([".pp.", "pwwp", ".pp."])

    // MARK: Camp

    static let fireOut = Bitmap.image([
        ".........",
        ".........",
        ".........",
        ".........",
        ".........",
        ".T.....T.",
        "..TtttT..",
        ".TtCCCtT.",
    ])
    static let fireA = Bitmap.image([
        "....o....",
        "...oo....",
        "...oyo...",
        "..oyyo...",
        "..oywyo..",
        ".ToyyyoT.",
        "..TtytT..",
        ".TtTTTtT.",
    ])
    static let fireB = Bitmap.image([
        "....o....",
        "....oo...",
        "...oyo...",
        "...oyyo..",
        "..oywyo..",
        ".ToyyyoT.",
        "..TtytT..",
        ".TtTTTtT.",
    ])
    static let shelter = Bitmap.image([
        ".........dd.........",
        "........dGGd........",
        ".......dGglGd.......",
        "......dGgggGGd......",
        ".....dGglgggGGd.....",
        "....dGgggglgGGGd....",
        "...dGgglTTTTgGGGd...",
        "..dGggggTkkTglGGGd..",
        ".dGglgggTkkTgggGGGd.",
        "dGggggggTkkTggggGGGd",
        "dddddddTTkkTTddddddd",
    ])
    static let dryingRack = Bitmap.image([
        "T..........T",
        "TttttttttttT",
        "T.e.e.e.e.eT",
        "T.e.e.e.e.eT",
        "T.E.E.E.E.ET",
        "T..........T",
        "T..........T",
        "k..........k",
    ])
    static let clayPot = Bitmap.image([
        ".RRRRR.",
        "RkkkkkR",
        ".RoooR.",
        "RoyoooR",
        "RoooooR",
        "RoooooR",
        ".RRRRR.",
    ])
    static let signalFrame = Bitmap.image([
        ".....TT.....",
        "....TttT....",
        "....TttT....",
        "...Tt..tT...",
        "...TtttTT...",
        "..Tt.tt.tT..",
        "..Tt.tt.tT..",
        ".TttttttttT.",
        ".Tt..tt..tT.",
        "Tt...tt...tT",
        "Tt...tt...tT",
    ])
    static let ship = Bitmap.image([
        "..........k...........",
        "..........kw..........",
        "..........kwww........",
        "......w...kwwwww......",
        ".....ww...kwwwwwww....",
        "....www...kwwwwwwww...",
        "...wwww...k...........",
        "..........k...........",
        "TTTTTTTTTTTTTTTTTTTTTT",
        ".TtttttwttttttwtttttT.",
        "..TttttttttttttttttT..",
        "...TTTTTTTTTTTTTTTT...",
    ])

    // MARK: World bits

    static let wave = Bitmap.image(["a.....", ".aaa.a"])
    static let star = Bitmap.image(["w"])
    static let zzz = Bitmap.image([
        "wwww....",
        "..w.....",
        ".w...www",
        "wwww..w.",
        ".....www",
    ])
    static let cloud: CGImage = {
        let width = 30, height = 15
        let puffs: [(Double, Double, Double)] = [(8, 9, 5.5), (15, 6, 6), (22, 9, 5.5), (15, 10, 5)]
        var pixels: [UInt32?] = []
        for y in 0..<height {
            for x in 0..<width {
                let inside = puffs.contains { hypot(Double(x) - $0.0, Double(y) - $0.1) <= $0.2 }
                pixels.append(inside ? (y > 10 ? 0xd8e8f5 : 0xffffff) : nil)
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }()
    static let mountain: CGImage = {
        let width = 56 * IslandMap.scale, height = 40 * IslandMap.scale
        var pixels = [UInt32?](repeating: nil, count: width * height)
        for y in 0..<height {
            let wobble = Double((y * 7919) % 7) - 3
            let half = 2 + Double(y) * 0.67 + wobble * 0.6
            let middle = width / 2
            let ridge = middle + ((y * 31) % 5) - 2 - y / 7
            let snow = height / 5 + ((y * 17) % 4)
            for x in 0..<width where abs(Double(x - middle)) <= half {
                let edge = abs(Double(x - middle)) > half - 1.5
                var color: UInt32 = x < ridge ? 0xbfb5aa : 0x8d827a
                if y < snow - abs(x - middle) / 3 { color = x < ridge ? 0xf4efe8 : 0xd5cdc4 }
                if (x * 13 + y * 7) % 23 == 0 { color = x < ridge ? 0xa99e93 : 0x7a7068 }
                pixels[y * width + x] = edge ? 0x5c524c : color
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }()

    // MARK: Icons

    static let heart = Bitmap.image([
        ".rr.rr.",
        "rwrrrrr",
        "rrrrrrr",
        ".rrrrR.",
        "..rrR..",
        "...R...",
    ])
    static let drop = Bitmap.image([
        "...A...",
        "..AAA..",
        ".AaAAA.",
        ".AaAAA.",
        ".AAAAA.",
        "..AAA..",
    ])
    static let fruit = Bitmap.image([
        "....G..",
        "...T...",
        ".rrTrr.",
        "rwrrrrR",
        "rrrrrRR",
        ".rrrRR.",
    ])
    static let moon = Bitmap.image([
        "..yyy..",
        ".yy....",
        "yy.....",
        "yy.....",
        ".yy..y.",
        "..yyy..",
    ])
    static let sun = Bitmap.image([
        "...o...",
        ".o.y.o.",
        "..yyy..",
        "oyyyyyo",
        "..yyy..",
        ".o.y.o.",
        "...o...",
    ])
    static let rain = Bitmap.image([
        "..www..",
        ".wwwww.",
        "wwwxxxx",
        "xxxxxxx",
        ".A.A.A.",
        "A.A.A..",
    ])
    static let log = Bitmap.image([
        ".......",
        ".TTTTT.",
        "TnTtttT",
        "TnTtttT",
        ".TTTTT.",
        ".......",
    ])
    static let dryLog = Bitmap.image([
        ".......",
        ".EEEEE.",
        "ENEeeeE",
        "ENEeeeE",
        ".EEEEE.",
        ".......",
    ])
    static let leaf = Bitmap.image([
        "....ll.",
        "..llgl.",
        ".lgglg.",
        ".lgGg..",
        ".gGg...",
        "T......",
    ])
    static let stone = Bitmap.image([
        ".......",
        "..CCC..",
        ".CvvcC.",
        "CvvccCC",
        ".CCCCC.",
        ".......",
    ])
    static let flame = Bitmap.image([
        "...o...",
        "..oo...",
        "..oyo..",
        ".oyyo..",
        ".oywyo.",
        "..oyo..",
    ])
    static let compass = Bitmap.image([
        "..kkk..",
        ".kwrwk.",
        "kwwrwwk",
        "kwwkwwk",
        ".kwwwk.",
        "..kkk..",
    ])
    static let check = Bitmap.image([
        "......g",
        ".....gg",
        "g...gg.",
        "gg.gg..",
        ".ggg...",
        "..g....",
    ])
    static let todo = Bitmap.image([
        ".......",
        ".ccccc.",
        ".c...c.",
        ".c...c.",
        ".ccccc.",
        ".......",
    ])

    static let hammer = Bitmap.image([
        ".CCCCC.",
        "CvvvvcC",
        ".CCtCC.",
        "...t...",
        "...t...",
        "...T...",
    ])
    static let fish = Bitmap.image([
        ".......",
        "B..bbb.",
        "BBbbbkb",
        "BBbxxxb",
        "B..bbb.",
        ".......",
    ])
    static let cross = Bitmap.image([
        "r.....r",
        ".r...r.",
        "..r.r..",
        "...r...",
        "..r.r..",
        ".r...r.",
        "r.....r",
    ])
    static let up = Bitmap.image([
        "...g...",
        "..ggg..",
        ".ggggg.",
        "...g...",
        "...g...",
        "...g...",
    ])
    static let hourglass = Bitmap.image([
        "TTTTT",
        ".yyy.",
        "..y..",
        "..y..",
        ".y.y.",
        "TTTTT",
    ])
    static let pause = Bitmap.image([
        "kk.kk",
        "kk.kk",
        "kk.kk",
        "kk.kk",
        "kk.kk",
        "kk.kk",
    ])
    static let play = Bitmap.image([
        "k....",
        "kkk..",
        "kkkkk",
        "kkkkk",
        "kkk..",
        "k....",
    ])
    static let skull = Bitmap.image([
        ".vvvvv.",
        "vvvvvvv",
        "vkkvkkv",
        "vkkvkkv",
        "vvvkvvv",
        ".vvvvv.",
        ".vkvkv.",
    ])
    static let storm = Bitmap.image([
        "..CCC..",
        ".CCCCC.",
        "CCCcccc",
        "ccccccc",
        "...yy..",
        "..yy...",
        "...y...",
    ])
    static let question = Bitmap.image([
        ".kkkkk.",
        "kyyyyyk",
        "kykkkyk",
        ".k.kyyk",
        "..kyyk.",
        "..kyk..",
        "..kkk..",
        "..kyk..",
        "..kkk..",
    ])
    static let peak = Bitmap.image([
        "...w...",
        "..www..",
        "..vcc..",
        ".vvccc.",
        ".vvcccC",
        "vvvccCC",
    ])
    static let treeIcon = Bitmap.image([
        "..ggg..",
        ".glggG.",
        "gggggGG",
        ".gGGGG.",
        "...T...",
        "...T...",
    ])
    static let palmIcon = Bitmap.image([
        ".gg.gg.",
        "g.ggg.g",
        "g..t..g",
        "...t...",
        "..t....",
        "..T....",
    ])
    static let waves = Bitmap.image([
        ".......",
        ".a...a.",
        "A.A.A.A",
        ".......",
        ".a...a.",
        "A.A.A.A",
    ])
    static let mapIcon = Bitmap.image([
        "NN.NN.N",
        "NnNNnNN",
        "NNgNNrN",
        "NggNnNN",
        "NNNNNnN",
        "N.NN.NN",
    ])
    static let arrows = Bitmap.image([
        "....k....",
        "...kkk...",
        ".k.....k.",
        "kk.....kk",
        ".k.....k.",
        "...kkk...",
        "....k....",
    ])

    /// A keyboard key with its legend, the one place a letter is the clearest picture.
    static func key(_ legend: String) -> CGImage {
        Bitmap.plate([PixelFont.image(legend)], face: 0xffffff, padding: 1)
    }
    static let spaceKey = Bitmap.plate([Bitmap.image([".........", ".........", "k.......k", "kkkkkkkkk"])], face: 0xffffff, padding: 2)

    static func number(_ value: Int, color: UInt32 = Ink.text) -> CGImage {
        PixelFont.image("\(value)", color: color)
    }

    static func icon(_ skill: Skill) -> CGImage {
        switch skill {
        case .foraging: leaf
        case .crafting: hammer
        case .exploration: compass
        case .survival: flame
        }
    }

    static func icon(_ region: Region) -> CGImage {
        switch region {
        case .beach: waves
        case .palmGrove: palmIcon
        case .stream: drop
        case .jungle: treeIcon
        case .ridge: stone
        case .summit: peak
        }
    }

    static func picture(_ structure: Structure) -> CGImage {
        switch structure {
        case .dryingRack: dryingRack
        case .shelter: shelter
        case .clayPot: clayPot
        case .signalFrame: signalFrame
        }
    }

    static func icon(_ item: Item) -> CGImage {
        switch item {
        case .water: drop
        case .food: fruit
        case .wood: log
        case .dryWood: dryLog
        case .fiber: leaf
        case .stone: stone
        }
    }
}
