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

    // Walked away from the crash in the suit they were wearing.

    /// The castaway never takes the suit off: hair becomes helmet, shirt and shorts become shell.
    private static func suited(_ rows: [String]) -> CGImage {
        let shell: [Character: Character] = ["h": "w", "T": "v", "R": "v", "r": "w", "B": "c", "p": "s"]
        return Bitmap.image(rows.map { String($0.map { shell[$0] ?? $0 }) })
    }

    private static let heroTop = [
        "............",
        "...kkkkkk...",
        "..khhThhhk..",
        ".khhhhhThhk.",
        ".khhsssshhk.",
        ".kskssssksk.",
        ".kspsssspsk.",
        "..kssssssk..",
        ".kkRRRRRRkk.",
        "ksRRRrrRRRsk",
        "kskRRkRRRksk",
        ".kkBBBBBBkk.",
    ]
    static let heroIdle = suited(heroTop + [
        "..kBBkkBBk..",
        "..ksk..ksk..",
        "..kkk..kkk..",
    ])
    static let heroStepA = suited(heroTop + [
        "..kBBkkBBk..",
        "..ksk..kkk..",
        "..kkk.......",
    ])
    static let heroStepB = suited(heroTop + [
        "..kBBkkBBk..",
        "..kkk..ksk..",
        ".......kkk..",
    ])
    // Walking away from us: the back of the hat and hair, no face.
    private static let heroBackTop = [
        "............",
        "...kkkkkk...",
        "..khhThhhk..",
        ".khhhhhThhk.",
        ".khhhhhhhhk.",
        ".khhhhhhhhk.",
        ".kshhhhhhsk.",
        "..khhhhhhk..",
        ".kkRRRRRRkk.",
        "ksRRRRRRRRsk",
        "kskRRkRRRksk",
        ".kkBBBBBBkk.",
    ]
    static let heroBackIdle = suited(heroBackTop + [
        "..kBBkkBBk..",
        "..ksk..ksk..",
        "..kkk..kkk..",
    ])
    static let heroBackStepA = suited(heroBackTop + [
        "..kBBkkBBk..",
        "..ksk..kkk..",
        "..kkk.......",
    ])
    static let heroBackStepB = suited(heroBackTop + [
        "..kBBkkBBk..",
        "..kkk..ksk..",
        ".......kkk..",
    ])

    // Seen from the side, facing right; flipped for left.
    private static let heroSideHead = [
        "............",
        "...kkkkkk...",
        "..khhThhhk..",
        ".khhhhhhhhk.",
        ".khhhhssssk.",
        ".khhhsssksk.",
        ".khhsssspsk.",
        "..khsssssk..",
    ]
    static let heroSideIdle = suited(heroSideHead + [
        "...kRRRRk...",
        "..kRRRsRk...",
        "..kRRRsRk...",
        "...kBBBBk...",
        "...kBBBk....",
        "...kskk.....",
        "...kkkk.....",
    ])
    /// Legs apart, front arm swung forward.
    static let heroSideStepA = suited(heroSideHead + [
        "...kRRRRk...",
        "..kRRRRRsk..",
        "..kRRRRRkk..",
        "...kBBBBk...",
        "..kBBkkBBk..",
        ".ksk...ksk..",
        ".kkk...kkkk.",
    ])
    /// Legs passing, arm swung back.
    static let heroSideStepB = suited(heroSideHead + [
        "...kRRRRk...",
        "..ksRRRRk...",
        "..kkRRRRk...",
        "...kBBBBk...",
        "...kBBBk....",
        "....ksk.....",
        "....kkkk....",
    ])
    // Working poses, side on.
    /// Arm drawn back, about to strike.
    static let heroArmUp = suited(heroSideHead + [
        "...kRRRRks..",
        "..kRRRRRk...",
        "..kRRRRRk...",
        "...kBBBBk...",
        "...kBBBk....",
        "...kskk.....",
        "...kkkk.....",
    ])
    /// Arm brought down in front.
    static let heroArmDown = suited(heroSideHead + [
        "...kRRRRk...",
        "..kRRRRRkk..",
        "..kRRRRRssk.",
        "...kBBBBk...",
        "...kBBBk....",
        "...kskk.....",
        "...kkkk.....",
    ])
    private static let heroLow = ["", "", "", ""] + heroSideHead
    /// Down on the heels, hands close.
    static let heroCrouch = suited(heroLow + [
        "..kRRRRRk...",
        "..kRRRssk...",
        ".kkBBBBkk...",
    ])
    /// Down on the heels, reaching for the ground.
    static let heroReach = suited(heroLow + [
        "..kRRRRRk...",
        "..kRRRRRsk..",
        ".kkBBBBkksk.",
    ])
    private static let heroBackHat = [
        "............",
        "...kkkkkk...",
        "..khhThhhk..",
        ".khhhhhThhk.",
    ]
    /// Shinning up a trunk, seen from behind: one hand high, then the other.
    static let heroClimbA = suited(heroBackHat + [
        "skhhhhhhhhk.",
        "kkhhhhhhhhks",
        ".kshhhhhhskk",
        "..khhhhhhk..",
        ".kkRRRRRRkk.",
        ".kRRRRRRRRk.",
        ".kkRRRRRRkk.",
        ".kkBBBBBBkk.",
        "..kBBkkBBk..",
        "..ksk..kkk..",
        "..kkk.......",
    ])
    static let heroClimbB = suited(heroBackHat + [
        ".khhhhhhhhks",
        "skhhhhhhhhkk",
        "kkshhhhhhsk.",
        "..khhhhhhk..",
        ".kkRRRRRRkk.",
        ".kRRRRRRRRk.",
        ".kkRRRRRRkk.",
        ".kkBBBBBBkk.",
        "..kBBkkBBk..",
        "..kkk..ksk..",
        ".......kkk..",
    ])

    // What goes in the hand.
    static let handAxe = Bitmap.image([
        ".CC",
        "CvC",
        ".TC",
        ".T.",
        ".T.",
        ".T.",
        ".T.",
    ])
    static let handStick = Bitmap.image([
        ".T.",
        ".T.",
        ".t.",
        ".T.",
        ".T.",
        ".T.",
        ".T.",
    ])
    static let rod = Bitmap.image([
        "..........Tv",
        ".........T.v",
        "........T..v",
        ".......T...v",
        "......T....v",
        ".....T.....v",
        "....T......v",
        "...T.......v",
        "..T........v",
        ".T.........v",
        "T..........v",
    ])
    static let float = Bitmap.image([".r.", "rrr", "www"])

    static let heroAsleep = Bitmap.image([
        "....kkkkkkkkkkk.",
        ".kkkwwwkvvvvvcck",
        "kvwwwsskvvvvvcck",
        ".kkkwwwkvvvvvcck",
        "....kkkkkkkkkkk.",
    ])

    // MARK: Plants and rocks


    // MARK: Giant trees

    /// The trees here dwarf a castaway, so they are grown from a recipe instead of drawn by hand.
    static let trees = (0..<3).map(makeTree)
    static let palms = (0..<3).map { makePalm($0, nuts: true) }
    /// The same palms after their coconuts have been taken.
    static let barePalms = (0..<3).map { makePalm($0, nuts: false) }

    private static func speck(_ x: Int, _ y: Int, _ salt: Int) -> Int {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ salt &* 2_246_822_519)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Int((h ^ (h >> 16)) & 0xff)
    }

    private static let leaves: [UInt32] = [0x2c5e34, 0x487f3f, 0x6f9f48, 0xa3c462]
    private static let leafEdge: UInt32 = 0x1f4a2a
    private static let bark: [UInt32] = [0x5c3a1e, 0x86592f, 0xa87a48]

    // Nothing that grows here is green. The shapes are borrowed from the deep sea and from fungi:
    // shelf brackets, gas bladders, tube worms. Violet and teal, with spots that glow.
    private static let ink: UInt32 = 0x1c1424
    private static let flesh: [UInt32] = [0x3a1f5c, 0x6b3fa0, 0xb07adf]
    private static let stalk: [UInt32] = [0x6f5f96, 0x9d8cc0, 0xcabfe0]
    private static let gill: [UInt32] = [0x1f6f78, 0x38b3b0]
    private static let glow: UInt32 = 0x9ff2e6

    /// A tower fungus: a ribbed stalk, shelves up its sides, and a spotted cap wide enough to stand under.
    private static func makeTree(_ variant: Int) -> CGImage {
        let width = 132, height = 150, middle = width / 2
        var pixels = [UInt32?](repeating: nil, count: width * height)
        func put(_ x: Int, _ y: Int, _ color: UInt32) {
            if x >= 0, y >= 0, x < width, y < height { pixels[y * width + x] = color }
        }

        // Stalk, flaring at the foot.
        for y in 44..<height - 1 {
            let flare = max(0, y - (height - 22))
            let half = 7 + flare * flare / 34
            let center = middle + Int((sin(Double(y) / 19 + Double(variant) * 2) * 2).rounded())
            for x in center - half...center + half {
                let across = Double(x - center + half) / Double(half * 2)
                var tone = across < 0.3 ? 2 : across < 0.7 ? 1 : 0
                if (x - center) % 4 == 0 { tone = max(0, tone - 1) }
                put(x, y, x == center - half || x == center + half || y == height - 2 ? ink : stalk[tone])
            }
        }

        // Shelves, alternating sides.
        for (index, level) in [112, 90, 70].enumerated() {
            let side = (index + variant) % 2 == 0 ? -1 : 1
            let reach = 24 + speck(index, variant, 5) % 10
            for step in 0...reach {
                let x = middle + side * (6 + step)
                let thick = Int((7 * sqrt(1 - pow(Double(step) / Double(reach), 2))).rounded())
                for dy in 0...thick {
                    let edge = dy == 0 || dy == thick || step == reach
                    put(x, level + dy - thick / 2, edge ? ink : dy < thick / 2 ? flesh[dy < 2 ? 2 : 1] : gill[(x + dy) % 2])
                }
            }
        }

        // The cap: a dome with a wavy skirt, gills showing underneath.
        let rx = Double(50 + variant * 5), ry = 34.0, top = 48.0
        for x in 0..<width {
            let u = (Double(x) - Double(middle)) / rx
            guard abs(u) < 1 else { continue }
            let crown = Int(top - ry * sqrt(1 - u * u))
            let skirt = Int(top + 5 + 3 * sin(Double(x) / 5 + Double(variant)))
            for y in crown...skirt + 4 {
                let v = (Double(y) - top) / ry
                if y > skirt {
                    put(x, y, y == skirt + 4 ? ink : gill[(x / 2) % 2])
                    continue
                }
                let light = -u * 0.55 - v * 0.8 + Double(speck(x, y, variant)) / 255 * 0.3 - 0.15
                // Spots of light, bigger toward the crown.
                let cellX = x / 13, cellY = (y + 60) / 11
                let spotX = cellX * 13 + 3 + speck(cellX, cellY, 9) % 7, spotY = cellY * 11 - 60 + 3 + speck(cellY, cellX, 4) % 5
                let spot = hypot(Double(x - spotX), Double(y - spotY)) < (v < -0.5 ? 2.6 : 1.7)
                let edge = y == crown || y == skirt || abs(u) > 0.985
                put(x, y, edge ? ink : spot ? glow : flesh[light > 0.45 ? 2 : light > -0.1 ? 1 : 0])
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }

    private static func makePalm(_ variant: Int, nuts: Bool) -> CGImage {
        let width = 170, height = 150
        var pixels = [UInt32?](repeating: nil, count: width * height)
        func put(_ x: Int, _ y: Int, _ color: UInt32) {
            if x >= 0, y >= 0, x < width, y < height { pixels[y * width + x] = color }
        }
        let foot = (x: Double(width / 2), y: Double(height - 2))
        let crown = (x: Double(width / 2 + 6 + variant * 3), y: 48.0)

        // A bowed, ringed stem, like kelp standing in air.
        for step in 0...400 {
            let along = Double(step) / 400
            let x = foot.x + (crown.x - foot.x) * along - sin(along * .pi) * 9
            let y = Int(foot.y + (crown.y - foot.y) * along)
            let half = Int((5.5 - 2.5 * along + max(0, 1 - along * 10) * 4).rounded())
            for dx in -half...half {
                let across = Double(dx + half) / Double(half * 2)
                let tone = y % 9 == 0 ? 0 : across < 0.35 ? 1 : 0
                put(Int(x) + dx, y, abs(dx) == half || step == 0 ? ink : y % 9 == 0 ? 0x154850 : gill[tone])
            }
        }

        // Tendrils arc out from the head, and a breath pod hangs at the end of each: full, or drawn down and slack.
        func pod(_ cx: Int, _ cy: Int, _ radius: Int) {
            for dy in -radius...radius {
                for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                    let far = dx * dx + dy * dy
                    let shine = dx < 0 && dy < 0 && far < radius * radius / 2 && far > radius * radius / 8
                    put(cx + dx, cy + dy, far > (radius - 1) * (radius - 1) ? ink
                        : !nuts ? flesh[0] : shine ? 0xf2fffb : dy > radius / 3 ? 0x5fc9c4 : glow)
                }
            }
        }
        for (index, degrees) in [100.0, 62, 138, 28, 168, 200, -14].enumerated() {
            let angle = (degrees + Double(variant) * 6) * .pi / 180
            let length = 34 + Double(speck(Int(degrees), variant, 3) % 16)
            var tip = (x: 0, y: 0)
            for step in 0..<Int(length * 3) {
                let along = Double(step) / (length * 3)
                tip = (Int(crown.x + cos(angle) * length * along), Int(crown.y - sin(angle) * length * along + 26 * along * along))
                put(tip.x, tip.y, flesh[1])
                put(tip.x, tip.y + 1, ink)
                put(tip.x, tip.y - 1, ink)
            }
            pod(tip.x, tip.y + (nuts ? 6 : 3), nuts ? 6 + (index + variant) % 4 : 3)
        }
        pod(Int(crown.x), Int(crown.y) - 2, nuts ? 11 : 5)
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }

    /// A dead giant: what is left is pale as bone and branched like coral.
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
                pixels[y * width + x] = rim ? ink : lit ? 0xe9e2f5 : dark ? 0x7f739c : 0xb9aed0
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
                pixels.append(dx * dx + dy * dy < 1 ? 0x1a1030 : nil)
            }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }()

    private static func alien(_ rows: [String]) -> CGImage {
        let inks: [Character: UInt32] = [
            "k": ink, "V": 0x3a1f5c, "v": 0x6b3fa0, "m": 0xb07adf, "t": 0x1f6f78, "T": 0x38b3b0, "c": glow,
            "o": 0xff8a4c, "y": 0xffd166, "w": 0xf2ecff, "p": 0xe85d9a, "r": 0xb3273c, "g": 0x8a8f9c, "G": 0x4b4f5c, "s": 0xdfe6f0,
        ]
        return Bitmap.image(width: rows[0].count, height: rows.count, pixels: rows.flatMap { $0.map { inks[$0] } })
    }

    /// A clump of polyps with fat orange bulbs you can eat.
    static let bush = alien([
        "..o...o..",
        ".kok.kok.",
        ".kVkkkVk.",
        "kVvVvVvVk",
        "kVVvVvVVk",
        ".kkkkkkk.",
    ])
    /// Ore: it grows in crystals here, and catches the light.
    static let rock = alien([
        "....k....",
        "..k.sk.k.",
        ".kskgGksk",
        ".kgGGGgGk",
        "kgGGsGGGk",
        ".kkkkkkk.",
    ])
    /// Tube worms: red plumes on pale tubes, tough enough to twist into line.
    static let fern = alien([
        "r.p.r.p",
        "prprprp",
        ".w.w.w.",
        ".w.w.w.",
        ".wkwkw.",
        ".kkkkk.",
    ])
    /// A shelf that fell off a tower fungus and dried where it lay.
    static let driftwood = alien([
        "....kkkkkk....",
        ".kkkmvvvvmkkk.",
        "kmvvvVvvVvvvmk",
        "kVVVVkVVVkVVVk",
        ".kkkk.kkk.kkk.",
    ])
    /// The pad from the pod's couch.
    static let bedroll = alien([
        ".kkkkkkkkkkkk.",
        "ksgsgsgsgsgsgk",
        "kgsgsgsgsgsgsk",
        "ksgsgsgsgsgsgk",
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
    /// Something small with a lit shell. It is food.
    static let shell = alien([".kkk.", "kcTck", "kTcTk", ".kkk."])

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

    // MARK: Sights

    /// A piece of the ship that came down somewhere else.
    static let wreck = Bitmap.image([
        "......................k....................",
        ".....................kk....................",
        "....................kCk....................",
        "...................kCk.....................",
        "......k...k...k...kCk......kkkkkkk.........",
        ".....kCk.kCk.kCk.kCk....kkkccccccCkk.......",
        "....kCk.kCk.kCk.kCkkkkkkccccccccccCCkk.....",
        "...kCkkkCkkkCkkkCcccccccccvccccvccccCCk....",
        "..kCccccccccccccccccccccccccccccccccCCCk...",
        "...kCCccccccccccccCCCCccccccccccccCCCCk....",
        "....kkCCCCCCCCCCCCkkkkCCCCCCCCCCCCCkkk.....",
        "......kkkkkkkkkkkk....kkkkkkkkkkkkk........",
    ])

    /// Someone was here before.
    static let bones = Bitmap.image([
        "..vv............",
        ".vkvk..v.v.v....",
        ".vvvv.vvvvvvv.vv",
        "..vv...v.v.v....",
    ])

    static let cave = Bitmap.image([
        "........CCCCCCCCCC........",
        "......CCcccccccccCCC......",
        "....CCccckkkkkkkkcccCC....",
        "...CccckkkkkkkkkkkkcccC...",
        "..CcckkkkkkkkkkkkkkkkccC..",
        "..CckkkkkkkkkkkkkkkkkkcC..",
        ".CcckkkkkkkkkkkkkkkkkkccC.",
        ".CckkkkkkkkkkkkkkkkkkkkcC.",
        ".CckkkkkkkkkkkkkkkkkkkkcC.",
        "CCckkkkkkkkkkkkkkkkkkkkcCC",
    ])

    /// Floaters: bags of gas that drift where there is something to eat.
    static let gullA = alien(["..kkk..", ".kmwmk.", "kmwmmmk", "kmmmmmk", ".kkkkk.", ".p.p.p.", "..p.p..", ".p...p."])
    static let gullB = alien(["..kkk..", ".kmwmk.", "kmwmmmk", "kmmmmmk", ".kkkkk.", "..p.p..", ".p.p.p.", "..p.p.."])

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
        let width = IslandMap.mountain.width, height = IslandMap.mountain.height
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
        "............",
        "..kk...kk...",
        ".krrk.krrk..",
        "krwrrkrrrrk.",
        "krrrrrrrrrk.",
        "krrrrrrrrRk.",
        ".krrrrrrRk..",
        "..krrrrRk...",
        "...krrRk....",
        "....kRk.....",
        ".....k......",
        "............",
    ])
    static let drop = Bitmap.image([
        ".....k......",
        "....kAk.....",
        "....kAk.....",
        "...kAAAk....",
        "...kaAAk....",
        "..kAaAAAk...",
        "..kaAAAAk...",
        ".kAaAAAABk..",
        ".kAAAAAABk..",
        ".kAAAAABBk..",
        "..kAABBBk...",
        "...kkkkk....",
    ])
    static let fruit = Bitmap.image([
        "......kk....",
        ".....kGgk...",
        "....kTkk....",
        "..kkkTkkk...",
        ".krrrkrrrk..",
        "krwrrrrrrRk.",
        "krwrrrrrrRk.",
        "krrrrrrrRRk.",
        "krrrrrrrRRk.",
        ".krrrrrRRk..",
        "..kkrRRkk...",
        "....kkk.....",
    ])
    static let moon = Bitmap.image([
        "....kkkk....",
        "..kkyyyk....",
        ".kyyykk.....",
        ".kyyk.......",
        "kyyyk.......",
        "kyyyk.......",
        "kyyyk.....k.",
        ".kyyyk...kyk",
        ".kyyyykkkyk.",
        "..kkyyyyyk..",
        "....kkkkk...",
        "............",
    ])
    static let sun = Bitmap.image([
        ".....o......",
        ".o...o...o..",
        "..o.....o...",
        "....kkkk....",
        "...kyyyyk...",
        "oo.kyyyyk.oo",
        "...kyyyyk...",
        "...kyyyyk...",
        "....kkkk....",
        "..o.....o...",
        ".o...o...o..",
        ".....o......",
    ])
    static let rain = Bitmap.image([
        "....kkkk....",
        "..kkwwwwkk..",
        ".kwwwwwwwwk.",
        "kwwwwxxxxxwk",
        "kxxxxxxxxxxk",
        ".kkkkkkkkkk.",
        "............",
        "..A..A..A...",
        ".A..A..A....",
        "............",
        "...A..A..A..",
        "..A..A..A...",
    ])
    static let log = Bitmap.image([
        "............",
        "............",
        "..kkkkkkkk..",
        ".knnkttttTk.",
        "knNNnkttttTk",
        "knNTnkTtttTk",
        "knNNnkttTtTk",
        ".knnkttttTk.",
        "..kkkkkkkk..",
        "............",
        "............",
        "............",
    ])
    static let dryLog = Bitmap.image([
        "............",
        "............",
        "..kkkkkkkk..",
        ".kNNkeeeeEk.",
        "kNwwNkeeEeEk",
        "kNwENkEeeeEk",
        "kNwwNkeeEeEk",
        ".kNNkeeeeEk.",
        "..kkkkkkkk..",
        "............",
        "............",
        "............",
    ])
    static let leaf = Bitmap.image([
        ".k...k...k..",
        "klk.klk.klk.",
        "kgk.kgk.kgk.",
        ".kgkkgkkgk..",
        ".kglkgklgk..",
        "..kgggggk...",
        "..knnnnnk...",
        "..kgggggk...",
        ".kgGkgkGgk..",
        ".kGkkgkkGk..",
        "..k.kGk.k...",
        ".....k......",
    ])
    static let stone = Bitmap.image([
        "............",
        "............",
        "....kkkk....",
        "..kkvvvvkk..",
        ".kvvvvvcckk.",
        ".kvvvvcccCk.",
        "kvvvvccccCCk",
        "kvvcccccCCCk",
        "kccccccCCCCk",
        ".kkCCCCCCkk.",
        "...kkkkkk...",
        "............",
    ])
    static let flame = Bitmap.image([
        ".....k......",
        "....kok.....",
        "....kook....",
        "...koook.k..",
        "..kooyookok.",
        "..koyyyooook",
        ".kooyyyyoook",
        ".koyywwyyook",
        ".koyywwyyook",
        ".kooyyyyook.",
        "..kkooookk..",
        "....kkkk....",
    ])
    static let compass = Bitmap.image([
        "....kkkk....",
        "..kkwwwwkk..",
        ".kwwwrwwwwk.",
        ".kwwwrrwwwk.",
        "kwwwwrrwwwwk",
        "kwwwwkkwwwwk",
        "kwwwwbbwwwwk",
        "kwwwwbbwwwwk",
        ".kwwwwbwwwk.",
        ".kwwwwbwwwk.",
        "..kkwwwwkk..",
        "....kkkk....",
    ])
    static let check = Bitmap.image([
        "............",
        "..........kk",
        ".........kgk",
        "........kgGk",
        ".kk....kgGk.",
        "kggk..kgGk..",
        "kgggkkgGk...",
        ".kgggggk....",
        "..kgggk.....",
        "...kgk......",
        "....k.......",
        "............",
    ])
    static let todo = Bitmap.image([
        "............",
        ".kkkkkkkkkk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kNNNNNNNNk.",
        ".kkkkkkkkkk.",
        "............",
    ])

    static let hammer = Bitmap.image([
        "............",
        ".kkkkkkkk...",
        "kvvvvvvcck..",
        "kvccccccCk..",
        ".kkktTkkkk..",
        "...ktTk.....",
        "...ktTk.....",
        "...ktTk.....",
        "...ktTk.....",
        "...ktTk.....",
        "...ktTk.....",
        "....kk......",
    ])
    static let fish = Bitmap.image([
        "............",
        "............",
        "k....kkkkk..",
        "kk..kbbbbbk.",
        "kBkkbbbbbkbk",
        "kBBbbbbbbbbk",
        "kBBbxxxxxxbk",
        "kBkkbxxxxxk.",
        "kk..kkbbkk..",
        "k.....kk....",
        "............",
        "............",
    ])
    static let cross = Bitmap.image([
        "............",
        ".kk......kk.",
        "krrk....krrk",
        ".krrk..krrk.",
        "..krrkkrrk..",
        "...krrrrk...",
        "...krrrrk...",
        "..krrkkrrk..",
        ".krrk..krrk.",
        "krrk....krrk",
        ".kk......kk.",
        "............",
    ])
    static let up = Bitmap.image([
        ".....kk.....",
        "....kggk....",
        "...kggggk...",
        "..kggggggk..",
        ".kggggggggk.",
        "kkkkggggkkkk",
        "...kggggk...",
        "...kggggk...",
        "...kggggk...",
        "...kggggk...",
        "...kkkkkk...",
        "............",
    ])
    static let hourglass = Bitmap.image([
        ".kkkkkkkkkk.",
        ".kTTTTTTTTk.",
        "..kwwwwwwk..",
        "..kwyyyywk..",
        "...kwyywk...",
        "....kyyk....",
        "....kwyk....",
        "...kwwywk...",
        "..kwwyywwk..",
        "..kyyyyyyk..",
        ".kTTTTTTTTk.",
        ".kkkkkkkkkk.",
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
        "....kkkk....",
        "..kkCCCCkk..",
        ".kCCCCCCCCk.",
        "kCCCCccccCCk",
        "kcccccccccck",
        ".kkkkkkkkkk.",
        ".....kyyk...",
        "....kyyk....",
        "...kyyyyk...",
        ".....kyyk...",
        "....kyk.....",
        "....kk......",
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
        ".....kk.....",
        "....kwwk....",
        "...kwwwwk...",
        "...kwvvck...",
        "..kvvvcck...",
        "..kvvvccck..",
        ".kvvvvcccCk.",
        ".kvvvccccCk.",
        "kvvvvcccCCCk",
        "kvvvccccCCCk",
        "kkkkkkkkkkkk",
        "............",
    ])
    static let treeIcon = Bitmap.image([
        "...kkkkkk...",
        "..kgglggGk..",
        ".kglggggGGk.",
        "kgggggggGGGk",
        "kggggggGGGGk",
        "kgggGGGGGGGk",
        ".kGGGGGGGGk.",
        "..kkkTTkkk..",
        "....ktTk....",
        "....ktTk....",
        "...kktTkk...",
        "...kkkkkk...",
    ])
    static let palmIcon = Bitmap.image([
        ".kkk....kkk.",
        "kgggk..kgggk",
        ".kkggkkggkk.",
        "kggkggggkggk",
        "kgk.kttk.kgk",
        ".k..ktTk..k.",
        "....ktTk....",
        "...ktTk.....",
        "...ktTk.....",
        "..ktTk......",
        "..ktTk......",
        "..kkkk......",
    ])
    static let waves = Bitmap.image([
        "............",
        "............",
        "..kk....kk..",
        ".kaak..kaak.",
        "kaAAakkaAAak",
        "kAkkAAAAkkAk",
        ".k..kkkk..k.",
        "..kk....kk..",
        ".kaak..kaak.",
        "kaAAakkaAAak",
        "kAkkAAAAkkAk",
        ".k..kkkk..k.",
    ])
    static let mapIcon = Bitmap.image([
        "............",
        ".kkk..kkkk..",
        "kNNNkkNNNNkk",
        "kNnNNNNrNNNk",
        "kNNgNNNNNnNk",
        "kNggNNnNNNNk",
        "kNNgNNNNgNNk",
        "kNNNNrNNggNk",
        "kNnNNNNNNNNk",
        "kNNNkkNNNNkk",
        ".kkk..kkkk..",
        "............",
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

    /// Hunger: an empty stomach, not a piece of food.
    static let stomach = Bitmap.image([
        "...kk.......",
        "..kppk......",
        "..kppk.kkk..",
        "..kppkkpppk.",
        "..kpppppppRk",
        ".kpppppppRRk",
        ".kppppppRRRk",
        ".kpppppRRRk.",
        "..kppRRRkk..",
        "kkkRRRkk....",
        "kRRkkk......",
        ".kk.........",
    ])
    /// Body heat.
    static let thermometer = Bitmap.image([
        "....kkkk....",
        "...kwwwwk...",
        "...kwwwwk.k.",
        "...kwrrwk...",
        "...kwrrwk.k.",
        "...kwrrwk...",
        "...kwrrwk.k.",
        "..kwwrrwwk..",
        ".kwrrrrrrwk.",
        ".kwrrrrrrwk.",
        "..kwrrrrwk..",
        "...kkkkkk...",
    ])
    /// Energy: how much is left in you.
    static let bolt = Bitmap.image([
        ".....kkkkk..",
        "....kyyyyk..",
        "...kyyyyk...",
        "..kyyyyk....",
        ".kyyyykkkk..",
        "kyyyyyyyyk..",
        "kkkkyyyyk...",
        "...kyyyk....",
        "..kyyyk.....",
        "..kyyk......",
        ".kyyk.......",
        ".kkk........",
    ])
    /// Foraging: a woven basket with something in it.
    static let basket = Bitmap.image([
        "....kkkk....",
        "..kkk..kkk..",
        ".kk......kk.",
        ".k.krk.krk.k",
        "kkkkkkkkkkkk",
        "knEnEnEnEnEk",
        "kEnEnEnEnEnk",
        ".knEnEnEnEk.",
        ".kEnEnEnEnk.",
        "..knEnEnEk..",
        "..kkkkkkkk..",
        "............",
    ])

    static func icon(_ skill: Skill) -> CGImage {
        switch skill {
        case .foraging: basket
        case .crafting: hammer
        case .exploration: compass
        case .survival: flame
        }
    }

    static func icon(_ region: Region) -> CGImage {
        switch region {
        case .landing: waves
        case .grove: palmIcon
        case .glacier: murkyDrop
        case .forest: treeIcon
        case .rim: stone
        case .vent: peak
        }
    }

    static let axe = Bitmap.image([
        "...kkkk.....",
        "..kvvvckk...",
        ".kvvvccCkk..",
        ".kvvccCktTk.",
        ".kccCCktTk..",
        "..kkkktTk...",
        "....ktTk....",
        "...ktTk.....",
        "..ktTk......",
        ".ktTk.......",
        "ktTk........",
        ".kk.........",
    ])
    static let rope = Bitmap.image([
        "...kkkkkk...",
        "..knnnnnnk..",
        ".knEkkkkEnk.",
        "knEk....kEnk",
        "knk..kk..knk",
        "knk.knnk.knk",
        "knEk.kk.kEnk",
        ".knEkkkkEnk.",
        "..knnnnnEnk.",
        "...kkkkkknnk",
        ".........kEk",
        "..........k.",
    ])
    /// Points the way in a thought; drawn pointing right and turned as needed.
    static let wayArrow = Bitmap.image([
        "....k....",
        "....kk...",
        "kkkkkyk..",
        "kyyyyyyk.",
        "kyyyyyyyk",
        "kyyyyyyk.",
        "kkkkkyk..",
        "....kk...",
        "....k....",
    ])
    /// Points down at the thing Space would use.
    static let pointer = Bitmap.image([
        "kkkkkkk",
        "kyyyyyk",
        ".kyyyk.",
        "..kyk..",
        "...k...",
    ])
    static let speaker = Bitmap.image([
        "...k...",
        "..kk.k.",
        "kkkk..k",
        "kkkk..k",
        "..kk.k.",
        "...k...",
    ])
    static let speakerOff = Bitmap.image([
        "...k...",
        "..kk...",
        "kkkkr.r",
        "kkkk.r.",
        "..kkr.r",
        "...k...",
    ])
    static let torch = Bitmap.image([
        ".....k......",
        "....kok.....",
        "...kooyk....",
        "...koyyok...",
        "..koyywyok..",
        "..kooyyook..",
        "...kkTTkk...",
        "....ktTk....",
        "....ktTk....",
        "....ktTk....",
        "....ktTk....",
        ".....kk.....",
    ])

    // MARK: Terraformers

    /// Heat first: a furnace that never goes out.
    static let warmer = Bitmap.image([
        "...kkkkkk...",
        "..kCCCCCCk..",
        "..kCooooCk..",
        "..kCoyyoCk..",
        "..kCoyyoCk..",
        "..kCooooCk..",
        "..kCCCCCCk..",
        ".kkCCCCCCkk.",
        ".kcCCkkCCck.",
        ".kcCCkkCCck.",
        "kkkkkkkkkkkk",
    ])
    /// Then water: a pump that brings the ice up as melt.
    static let thawer = Bitmap.image([
        "....kkkk....",
        "...kccck....",
        "...kcckkkkk.",
        "...kcckAAAk.",
        "...kcck.kAk.",
        "..kkcckk.k..",
        "..kCCCCk.A..",
        "..kCAACk....",
        "..kCAACk.A..",
        ".kkCCCCkk...",
        "kkkkkkkkkkkk",
    ])
    /// Then life: a dish of spores for the wind.
    static let seeder = Bitmap.image([
        ".....l......",
        "....lGl.l...",
        ".....GlGl...",
        ".....G.G....",
        "..kkkGkGkk..",
        ".kCCCCCCCCk.",
        ".kCccccccCk.",
        "..kCCCCCCk..",
        "...kkCCkk...",
        "....kCCk....",
        "..kkkkkkkk..",
    ])
    /// The planet, once it is one you can live on.
    static let planet = Bitmap.image([
        "....kkkk....",
        "..kkAAAAkk..",
        ".kAAGGAAAAk.",
        ".kAGGGGAAAk.",
        "kAAGGGAAAGAk",
        "kAAAGAAAGGAk",
        "kAAAAAAGGGAk",
        "kAGAAAAAGGAk",
        ".kGGAAAAAAk.",
        ".kAGGAAAAAk.",
        "..kkAAAAkk..",
        "....kkkk....",
    ])

    static func picture(_ structure: Structure) -> CGImage {
        switch structure {
        case .cutter: axe
        case .tether: rope
        case .lamp: torch
        case .map: mapIcon
        case .smelter: dryingRack
        case .dome: shelter
        case .electrolyzer: clayPot
        case .warmer: warmer
        case .thawer: thawer
        case .seeder: seeder
        }
    }

    /// Stream water: not safe until boiled.
    static let murkyDrop = Bitmap.image([
        ".....k......",
        "....kEk.....",
        "....kEk.....",
        "...kEEEk....",
        "...keEEk....",
        "..kEeEEEk...",
        "..keEETEk...",
        ".kEeEEEETk..",
        ".kEETEEETk..",
        ".kEEEEETTk..",
        "..kEETTTk...",
        "...kkkkk....",
    ])
    static let coconut = Bitmap.image([
        "............",
        "...kkkkkk...",
        "..khhhhhhk..",
        ".khhthhhhhk.",
        "khhttthhhhhk",
        "khhthhhhhhhk",
        "khhhhhhhhTTk",
        "khhhhkhkhTTk",
        ".khhhhhhTTk.",
        "..khhhkTTk..",
        "...kkkkkk...",
        "............",
    ])

    static func icon(_ item: Item) -> CGImage {
        switch item {
        case .ice: murkyDrop
        case .air: drop
        case .food: fruit
        case .biomass: log
        case .metal: dryLog
        case .fiber: leaf
        case .ore: stone
        }
    }
}
