import SpriteKit

/// How the castaway got here, told without a word: a ship over a dead world, a burning fall, a pod in the dust.
/// Hangs on the camera and covers the whole view until it fades into the game.
final class Intro: SKNode {
    private let view: CGSize
    private var finish: (() -> Void)?
    private let horizon: CGFloat = -20

    private let sky = SKSpriteNode(color: Intro.color(0x0b1020), size: .zero)
    private let sea = SKSpriteNode(color: Intro.color(0x7a3f33), size: .zero)
    private let sun = SKSpriteNode()
    private let land = SKSpriteNode()
    private let calm = SKNode(), rough = SKNode()
    private let boat = SKSpriteNode(), berth = SKNode()
    private let drifter = SKSpriteNode()
    private let rain = SKNode()
    private let flash = SKSpriteNode(color: .white, size: .zero)
    private let dark = SKSpriteNode(color: .black, size: .zero)

    init(size: CGSize, finish: @escaping () -> Void) {
        view = size
        self.finish = finish
        super.init()
        build()
        play()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Cuts straight to the beach.
    func skip() {
        removeAllActions()
        end(seconds: 0.25)
    }

    private func end(seconds: Double) {
        run(.sequence([.fadeOut(withDuration: seconds), .removeFromParent()]))
        finish?()
        finish = nil
    }

    // MARK: The pictures

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    private func texture(_ image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    private func picture(_ node: SKSpriteNode, _ image: CGImage, scale: CGFloat) {
        node.texture = texture(image)
        node.size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    private static func drawing(_ rows: [String], _ inks: [Character: UInt32]) -> CGImage {
        Bitmap.image(width: rows[0].count, height: rows.count, pixels: rows.flatMap { $0.map { inks[$0] } })
    }

    /// A row of swell that can slide sideways forever.
    private static func swell(width: Int, rise: Double, length: Int, body: UInt32, foam: UInt32) -> CGImage {
        let height = Int(rise) + 110
        var pixels = [UInt32?](repeating: nil, count: width * height)
        for x in 0..<width {
            let top = Int((rise * (0.5 - 0.5 * sin(Double(x) / Double(length) * 2 * .pi))).rounded())
            for y in top..<height { pixels[y * width + x] = y < top + 2 ? foam : body }
        }
        return Bitmap.image(width: width, height: height, pixels: pixels)
    }

    private func swell(in layer: SKNode, rise: Double, length: Int, body: UInt32, foam: UInt32, top: CGFloat, seconds: Double, z: CGFloat) {
        let image = Intro.swell(width: Int(view.width) + length * 2, rise: rise, length: length, body: body, foam: foam)
        let node = SKSpriteNode(texture: texture(image))
        node.anchorPoint = CGPoint(x: 0, y: 1)
        node.position = CGPoint(x: -view.width / 2 - CGFloat(length), y: top)
        node.zPosition = z
        node.run(.repeatForever(.sequence([.moveBy(x: -CGFloat(length), y: 0, duration: seconds), .moveBy(x: CGFloat(length), y: 0, duration: 0)])))
        layer.addChild(node)
    }

    private func build() {
        zPosition = 29500
        for (node, z) in [(sky, 0), (flash, 8), (dark, 9)] as [(SKSpriteNode, CGFloat)] {
            node.size = CGSize(width: view.width + 8, height: view.height + 8)
            node.zPosition = z
            addChild(node)
        }
        flash.alpha = 0
        dark.alpha = 0

        var disc = [UInt32?](repeating: nil, count: 28 * 28)
        for index in disc.indices where hypot(Double(index % 28) - 13.5, Double(index / 28) - 13.5) < 13.6 { disc[index] = 0xf3dcab }
        picture(sun, Bitmap.image(width: 28, height: 28, pixels: disc), scale: 1)
        sun.position = CGPoint(x: 120, y: horizon + 60)
        sun.setScale(0.4)
        // Stars, until the air starts to burn.
        for index in 0..<50 {
            let star = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            star.position = CGPoint(x: CGFloat(index * 131 % Int(view.width)) - view.width / 2, y: horizon + 8 + CGFloat(index * 53 % 140))
            star.alpha = 0.4 + CGFloat(index % 5) * 0.12
            star.zPosition = 0.5
            star.name = "star"
            addChild(star)
        }
        sun.zPosition = 1
        addChild(sun)

        // A mesa, far off.
        var shape = [UInt32?](repeating: nil, count: 64 * 24)
        for x in 0..<64 {
            for y in (23 - Int(9 * sin(Double(x) / 63 * .pi)))..<24 { shape[y * 64 + x] = 0x7d4a3c }
        }
        picture(land, Bitmap.image(width: 64, height: 24, pixels: shape), scale: 2)
        land.anchorPoint = CGPoint(x: 0.5, y: 0)
        land.position = CGPoint(x: 150, y: horizon - 2)
        land.zPosition = 2
        land.alpha = 0
        addChild(land)

        sea.size = CGSize(width: view.width + 8, height: view.height / 2 + horizon + 8)
        sea.anchorPoint = CGPoint(x: 0.5, y: 1)
        sea.position = CGPoint(x: 0, y: horizon)
        sea.zPosition = 3
        addChild(sea)

        swell(in: calm, rise: 4, length: 48, body: 0x86483a, foam: 0xa85f48, top: horizon - 18, seconds: 3.2, z: 4)
        swell(in: calm, rise: 5, length: 64, body: 0x92503f, foam: 0xb86c50, top: horizon - 44, seconds: 2.4, z: 6)
        swell(in: rough, rise: 14, length: 96, body: 0x5a2c26, foam: 0x8a4a3a, top: horizon - 6, seconds: 0.7, z: 4)
        swell(in: rough, rise: 18, length: 120, body: 0x4a221e, foam: 0x9a5540, top: horizon - 34, seconds: 0.5, z: 6)
        rough.alpha = 0
        addChild(calm)
        addChild(rough)

        let pod = Intro.drawing([
            "....kkkkkk......",
            "..kkwwwwwwkk....",
            ".kwwwwAAwwwwkk..",
            "kvwwwwAAwwwwwwko",
            ".kvvwwwwwwwwkk..",
            "..kkvvvvvvkk....",
            "....kkkkkk......",
        ], ["k": 0x2a2a33, "w": 0xdfe3e8, "v": 0xaab2bb, "A": 0x4a9bdc, "o": 0xf08a3c])
        picture(boat, pod, scale: 3)
        berth.position = CGPoint(x: -170, y: horizon + 70)
        berth.zPosition = 5
        berth.addChild(boat)
        addChild(berth)
        rock(boat, lift: 2, lean: 0.05, seconds: 1.1)

        // The pod where it came down, nose in the dust.
        picture(drifter, pod, scale: 3)
        drifter.zRotation = -0.5
        drifter.position = CGPoint(x: -10, y: horizon - 30)
        drifter.zPosition = 5
        drifter.alpha = 0
        addChild(drifter)

        rain.zPosition = 7
        rain.alpha = 0
        addChild(rain)
        for index in 0..<140 {
            let drop = SKSpriteNode(color: NSColor(red: 1, green: 0.7, blue: 0.35, alpha: 0.8), size: CGSize(width: 1, height: 5))
            let x = CGFloat((index * 197 + index * index * 31) % Int(view.width + 120)) - view.width / 2
            drop.run(.sequence([
                .wait(forDuration: Double(index * 7 % 23) * 0.02),
                .repeatForever(.sequence([
                    .move(to: CGPoint(x: x, y: view.height / 2 + 6), duration: 0),
                    .move(to: CGPoint(x: x - 110, y: -view.height / 2 - 6), duration: 0.38 + Double(index % 5) * 0.04),
                ])),
            ]))
            rain.addChild(drop)
        }
    }

    private func rock(_ node: SKNode, lift: CGFloat, lean: CGFloat, seconds: Double) {
        let up = SKAction.group([.moveBy(x: 0, y: lift, duration: seconds), .rotate(toAngle: lean, duration: seconds)])
        let down = SKAction.group([.moveBy(x: 0, y: -lift, duration: seconds), .rotate(toAngle: -lean, duration: seconds)])
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "rock")
    }

    // MARK: The story

    private func play() {
        func tint(_ node: SKSpriteNode, _ hex: UInt32, _ seconds: Double) {
            node.run(.colorize(with: Intro.color(hex), colorBlendFactor: 1, duration: seconds))
        }
        func lightning() -> SKAction {
            .run { [flash] in flash.run(.sequence([.fadeAlpha(to: 0.9, duration: 0.04), .fadeAlpha(to: 0.2, duration: 0.08),
                                                   .fadeAlpha(to: 0.7, duration: 0.04), .fadeOut(withDuration: 0.3)])) }
        }
        // High over a dead world, coming in.
        berth.run(.moveBy(x: 150, y: -40, duration: 7.4))
        run(.sequence([
            .wait(forDuration: 3.4),
            // The air catches fire around the hull.
            .run { [self] in
                Sound.shared.play(.night)
                tint(sky, 0x5a2416, 1.6)
                tint(sea, 0x4a221e, 1.6)
                sun.run(.fadeOut(withDuration: 1))
                children.filter { $0.name == "star" }.forEach { $0.run(.fadeOut(withDuration: 1)) }
                calm.run(.fadeOut(withDuration: 1.6))
                rough.run(.fadeIn(withDuration: 1.6))
                rain.run(.fadeIn(withDuration: 1.2))
                boat.removeAction(forKey: "rock")
                rock(boat, lift: 9, lean: 0.32, seconds: 0.55)
            },
            .wait(forDuration: 1.8), lightning(),
            .wait(forDuration: 1.3), lightning(),
            .wait(forDuration: 0.9), lightning(),
            // Too fast, too steep.
            .run { [self] in
                Sound.shared.play(.lost)
                boat.removeAction(forKey: "rock")
                boat.run(.group([.rotate(toAngle: -0.9, duration: 0.5), .moveBy(x: 90, y: -120, duration: 1.1), .fadeOut(withDuration: 1.2)]))
            },
            .wait(forDuration: 1.3),
            .run { [dark] in dark.run(.fadeIn(withDuration: 0.5)) },
            .wait(forDuration: 1.3),
            // Morning. Dust, the pod, and nobody else.
            .run { [self] in
                Sound.shared.play(.morning)
                sky.removeAllActions()
                sea.removeAllActions()
                sky.color = Intro.color(0xc99a78)
                sea.color = Intro.color(0x7a3f33)
                rough.alpha = 0
                rain.alpha = 0
                calm.alpha = 1
                land.alpha = 1
                drifter.alpha = 1
                calm.children.forEach { $0.removeAllActions() }
                dark.run(.fadeOut(withDuration: 1))
            },
            .wait(forDuration: 4.4),
            .run { [self] in end(seconds: 1) },
        ]))
    }
}
