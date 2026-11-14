import CoreGraphics
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
    static let heroAsleep = Bitmap.image([
        "....kkkkkkkkkkk.",
        ".kkkeeekrrrrrbbk",
        "kEeeesskrrrrrbbk",
        ".kkkeeekrrrrrbbk",
        "....kkkkkkkkkkk.",
    ])

    // MARK: Plants and rocks

    static let palm = Bitmap.image([
        "....dd....dd....",
        "..ddGGd..dGGdd..",
        ".dGGggGddGggGGd.",
        "dGgglggGGgglggGd",
        "dGgGdGggggGdGgGd",
        "dGd.dGgttgGd.dGd",
        ".d..dGdtTdGd..d.",
        "....dd.tT.dd....",
        ".......tT.......",
        "......ttT.......",
        "......tT........",
        "......tT........",
        ".....ttT........",
        ".....tTT........",
        "....kTTTk.......",
    ])
    static let tree = Bitmap.image([
        "....ddddd....",
        "..ddGgggGdd..",
        ".dGgglgggGGd.",
        ".dgglggggGGd.",
        "dGgggggggGGGd",
        "dGggggggGGGGd",
        "dGGgggGGGGGdd",
        ".dGGGGGGGGGd.",
        "..dddGGGddd..",
        ".....tTT.....",
        ".....tTT.....",
        "....ktTTk....",
    ])
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
    static let flowerPink = Bitmap.image([".p.", "pyp", ".p."])
    static let flowerWhite = Bitmap.image([".w.", "wyw", ".w."])
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
