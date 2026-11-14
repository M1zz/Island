import IslandCore
import SpriteKit

/// The island as you see it. It only draws; every rule lives in `GameEngine`.
final class IslandScene: SKScene {
    var onTick: ((TimeInterval) -> Void)?

    private let mapWidth = CGFloat(IslandMap.width)
    private let mapHeight = CGFloat(IslandMap.height)
    private let eye = SKCameraNode()
    private var workOrigin: CGPoint?
    private var lastUpdate: TimeInterval?

    private let hero = SKSpriteNode()
    private let zzz = SKSpriteNode()
    private let progressBack = SKSpriteNode(color: NSColor(white: 0.15, alpha: 1), size: CGSize(width: 18, height: 4))
    private let progressFill = SKSpriteNode(color: NSColor(red: 0.55, green: 0.85, blue: 0.3, alpha: 1), size: CGSize(width: 16, height: 2))
    private let prompt = SKSpriteNode()
    private var promptText = ""
    private var propNodes: [SKSpriteNode] = []
    private let fire = SKSpriteNode()
    private let glow = SKSpriteNode()
    private let signalFire = SKSpriteNode()
    private let ship = SKSpriteNode()
    private let skyTint = SKSpriteNode(color: .white, size: .zero)
    private let rain = SKNode()
    private let fireflies = SKNode()
    private var clouds: [Region: SKNode] = [:]
    private var fog: [Region: SKSpriteNode] = [:]
    private var labels: [Region: (name: SKSpriteNode, unknown: SKSpriteNode)] = [:]
    private let mapLayer = SKNode()
    private var mapOpen = false
    private var built: [Structure: SKSpriteNode] = [:]

    private var fireLit = false
    private var stormy = false
    private var asleep = false

    private lazy var idleTexture = texture(Art.heroIdle)
    private lazy var stepTextures = [texture(Art.heroStepA), texture(Art.heroStepB)]
    private lazy var fireTextures = [texture(Art.fireA), texture(Art.fireB)]

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = NSColor(red: 0.29, green: 0.61, blue: 0.86, alpha: 1)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Helpers

    private func texture(_ image: CGImage) -> SKTexture {
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// Map pixels (y down) to scene points (y up).
    private func point(_ x: Int, _ y: Int) -> CGPoint {
        CGPoint(x: CGFloat(x), y: mapHeight - CGFloat(y))
    }

    private func spot(_ region: Region) -> CGPoint {
        let anchor = IslandMap.anchor(region)
        return point(anchor.x, anchor.y)
    }

    /// Where the castaway's feet are, in map pixels.
    var heroSpot: (x: Int, y: Int) {
        (Int(hero.position.x.rounded()), Int((mapHeight - hero.position.y).rounded()))
    }

    /// A sprite standing on the ground at a map pixel, sorted by how far down the screen it is.
    @discardableResult
    private func place(_ node: SKSpriteNode, _ image: CGImage, x: Int, y: Int) -> SKSpriteNode {
        node.texture = texture(image)
        node.size = CGSize(width: image.width, height: image.height)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = point(x, y)
        node.zPosition = CGFloat(y)
        if node.parent == nil { addChild(node) }
        return node
    }

    private func bob(_ node: SKNode, by distance: CGFloat, every seconds: TimeInterval) {
        let up = SKAction.moveBy(x: 0, y: distance, duration: seconds)
        up.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, up.reversed()])))
    }

    // MARK: Building the world

    private func build() {
        let terrain = SKSpriteNode(texture: texture(IslandMap.terrain))
        terrain.position = CGPoint(x: mapWidth / 2, y: mapHeight / 2)
        terrain.zPosition = -1000
        addChild(terrain)
        addChild(eye)
        camera = eye

        var seed: UInt64 = 99
        func roll() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }

        // Waves that come and go.
        var waves = 0
        while waves < 700 {
            let x = Int(roll() * mapWidth), y = Int(roll() * mapHeight)
            guard IslandMap.shore(x, y) > 1.16 else { continue }
            waves += 1
            let wave = SKSpriteNode(texture: texture(Art.wave))
            wave.position = point(x, y)
            wave.zPosition = -900
            wave.alpha = 0
            let drift = SKAction.group([
                .sequence([.fadeAlpha(to: 0.9, duration: 1.2), .fadeOut(withDuration: 1.2)]),
                .moveBy(x: -5, y: 0, duration: 2.4),
            ])
            wave.run(.sequence([
                .wait(forDuration: Double(roll()) * 4),
                .repeatForever(.sequence([drift, .moveBy(x: 5, y: 0, duration: 0), .wait(forDuration: 1 + Double(roll()) * 3)])),
            ]))
            addChild(wave)
        }

        for prop in IslandMap.props {
            let image: CGImage
            switch prop.prop {
            case .palm: image = Art.palm
            case .tree: image = Art.tree
            case .bush: image = Art.bush
            case .rock: image = Art.rock
            case .fern: image = Art.fern
            case .flowerPink: image = Art.flowerPink
            case .flowerWhite: image = Art.flowerWhite
            case .shell: image = Art.shell
            }
            propNodes.append(place(SKSpriteNode(), image, x: prop.x, y: prop.y))
        }

        place(SKSpriteNode(), Art.mountain, x: IslandMap.peak.x, y: IslandMap.peak.y)

        // Camp
        let bed = IslandMap.bed
        place(fire, Art.fireOut, x: IslandMap.fire.x, y: IslandMap.fire.y)
        place(SKSpriteNode(), Art.bedroll, x: bed.x, y: bed.y)
        built[.shelter] = place(SKSpriteNode(), Art.shelter, x: bed.x, y: bed.y - 4)
        built[.dryingRack] = place(SKSpriteNode(), Art.dryingRack, x: IslandMap.fire.x + 20, y: IslandMap.fire.y - 10)
        built[.clayPot] = place(SKSpriteNode(), Art.clayPot, x: IslandMap.fire.x + 12, y: IslandMap.fire.y + 5)
        let signal = IslandMap.signal
        place(SKSpriteNode(), Art.cairn, x: signal.x, y: signal.y)
        built[.signalFrame] = place(SKSpriteNode(), Art.signalFrame, x: signal.x, y: signal.y - 1)

        place(signalFire, Art.fireA, x: signal.x, y: signal.y - 4)
        signalFire.setScale(2)
        signalFire.zPosition = CGFloat(signal.y) + 1
        signalFire.run(.repeatForever(.animate(with: fireTextures, timePerFrame: 0.16)))

        place(hero, Art.heroIdle, x: IslandMap.start.x, y: IslandMap.start.y)

        prompt.anchorPoint = CGPoint(x: 0.5, y: 0)
        prompt.zPosition = 6600
        prompt.isHidden = true
        addChild(prompt)

        zzz.texture = texture(Art.zzz)
        zzz.size = CGSize(width: Art.zzz.width, height: Art.zzz.height)
        zzz.zPosition = 5500
        addChild(zzz)
        bob(zzz, by: 3, every: 0.8)

        progressBack.zPosition = 6500
        progressFill.zPosition = 6501
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        addChild(progressBack)
        addChild(progressFill)

        // Fog of war
        for region in Region.allCases where region != .beach {
            let blanket = SKSpriteNode(texture: texture(IslandMap.fog(over: region)))
            blanket.position = CGPoint(x: mapWidth / 2, y: mapHeight / 2)
            blanket.size = CGSize(width: mapWidth, height: mapHeight)
            blanket.zPosition = -500
            fog[region] = blanket
            addChild(blanket)

            let group = SKNode()
            var spots: [(Int, Int)] = []
            while spots.count < 70 {
                let x = Int(roll() * mapWidth), y = Int(roll() * mapHeight)
                if IslandMap.region(x: x, y: y) == region { spots.append((x, y)) }
            }
            for (index, spot) in spots.enumerated() {
                let cloud = SKSpriteNode(texture: texture(Art.cloud))
                cloud.position = point(spot.0, spot.1)
                cloud.zPosition = CGFloat(spot.1)
                let drift = SKAction.moveBy(x: index.isMultiple(of: 2) ? 3 : -3, y: 0, duration: 2.5 + Double(index) * 0.3)
                drift.timingMode = .easeInEaseOut
                cloud.run(.repeatForever(.sequence([drift, drift.reversed()])))
                group.addChild(cloud)
            }
            clouds[region] = group
            addChild(group)

        }

        // Names and question marks that only show on the zoomed-out map.
        mapLayer.zPosition = 6900
        mapLayer.alpha = 0
        addChild(mapLayer)
        for region in Region.allCases {
            let name = SKSpriteNode(texture: texture(PixelFont.image(region.displayName, color: 0xffffff, outline: 0x3b2416)))
            let unknown = SKSpriteNode(texture: texture(PixelFont.image("?", color: 0xf9d65c, outline: 0x3b2416)))
            name.setScale(CGFloat(IslandMap.scale))
            unknown.setScale(CGFloat(IslandMap.scale) * 2)
            name.position = spot(region)
            unknown.position = spot(region)
            labels[region] = (name, unknown)
            mapLayer.addChild(name)
            mapLayer.addChild(unknown)
        }

        // Light
        skyTint.size = CGSize(width: size.width + 4, height: size.height + 4)
        skyTint.zPosition = 7000
        skyTint.blendMode = .multiply
        eye.addChild(skyTint)

        glow.texture = texture(Self.glowImage)
        glow.size = CGSize(width: 72, height: 72)
        glow.position = CGPoint(x: fire.position.x, y: fire.position.y + 4)
        glow.zPosition = 7100
        glow.blendMode = .add
        addChild(glow)
        glow.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 0.3), .scale(to: 0.97, duration: 0.25)])))

        fireflies.zPosition = 7200
        eye.addChild(fireflies)
        for _ in 0..<26 {
            let fly = SKSpriteNode(color: NSColor(red: 1, green: 0.95, blue: 0.5, alpha: 1), size: CGSize(width: 1, height: 1))
            fly.position = CGPoint(x: (roll() - 0.5) * size.width, y: (roll() - 0.5) * size.height)
            fly.blendMode = .add
            fly.alpha = 0
            let wander = SKAction.moveBy(x: (roll() - 0.5) * 14, y: (roll() - 0.5) * 10, duration: 2.2)
            fly.run(.sequence([
                .wait(forDuration: Double(roll()) * 3),
                .repeatForever(.sequence([
                    .group([.fadeIn(withDuration: 0.6), wander]),
                    .group([.fadeOut(withDuration: 0.8), wander.reversed()]),
                    .wait(forDuration: Double(roll()) * 2),
                ])),
            ]))
            fireflies.addChild(fly)
        }

        rain.zPosition = 7300
        rain.position = CGPoint(x: -size.width / 2, y: -size.height / 2)
        eye.addChild(rain)
        for _ in 0..<70 {
            let drop = SKSpriteNode(color: NSColor(red: 0.8, green: 0.92, blue: 1, alpha: 0.75), size: CGSize(width: 1, height: 4))
            let x = roll() * (size.width + 60)
            let fall = SKAction.sequence([
                .move(to: CGPoint(x: x, y: size.height + 6), duration: 0),
                .move(to: CGPoint(x: x - 60, y: -6), duration: 0.55 + Double(roll()) * 0.25),
            ])
            drop.position = CGPoint(x: x, y: size.height + 6)
            drop.run(.sequence([.wait(forDuration: Double(roll())), .repeatForever(fall)]))
            rain.addChild(drop)
        }

        ship.texture = texture(Art.ship)
        ship.size = CGSize(width: Art.ship.width, height: Art.ship.height)
        ship.zPosition = 4000
        addChild(ship)
        bob(ship, by: 1, every: 0.7)

        reset()
    }

    /// A soft round light, stepped into bands so it still reads as pixels.
    private static let glowImage: CGImage = {
        let side = 36
        var pixels: [UInt32?] = []
        for y in 0..<side {
            for x in 0..<side {
                let distance = hypot(Double(x) - 17.5, Double(y) - 17.5) / 18
                let band = (max(0, 1 - distance) * 5).rounded(.down) / 5
                let red = UInt32(255 * band * 0.75), green = UInt32(170 * band * 0.75), blue = UInt32(70 * band * 0.75)
                pixels.append(red << 16 | green << 8 | blue)
            }
        }
        return Bitmap.image(width: side, height: side, pixels: pixels)
    }()

    // MARK: Following the game

    func reset() {
        stormy = false
        asleep = false
        hero.removeAllActions()
        hero.zRotation = 0
        hero.xScale = 1
        hero.texture = idleTexture
        hero.size = idleTexture.size()
        hero.position = point(IslandMap.start.x, IslandMap.start.y)
        workOrigin = nil
        follow()
        zzz.isHidden = true
        setPrompt(nil, enabled: true)
        ship.removeAction(forKey: "sail")
        ship.isHidden = true
        signalFire.isHidden = true
        setProgress(nil)
        for cover in Array(clouds.values) + Array(fog.values) as [SKNode] {
            cover.removeAllActions()
            cover.alpha = 1
            cover.isHidden = false
        }
    }

    func sync(state: GameState) {
        for region in Region.allCases {
            let known = state.discovered.contains(region)
            labels[region]?.name.isHidden = !known
            labels[region]?.unknown.isHidden = known
            if known, let cloud = clouds[region], let blanket = fog[region], !blanket.isHidden, !blanket.hasActions() {
                let lift = SKAction.sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 1.2), .hide()])
                cloud.run(lift)
                blanket.run(lift)
            }
        }
        for (node, prop) in zip(propNodes, IslandMap.props) {
            node.isHidden = !state.discovered.contains(prop.region)
        }
        for (structure, node) in built {
            node.isHidden = !state.has(structure)
        }
        if fireLit != state.fireLitToday || fire.texture == nil {
            fireLit = state.fireLitToday
            fire.removeAllActions()
            if fireLit {
                fire.run(.repeatForever(.animate(with: fireTextures, timePerFrame: 0.16)))
            } else {
                fire.texture = texture(Art.fireOut)
            }
        }
    }

    /// `hour` runs 0..<24. Colors the whole island for that time of day.
    func setSky(hour: Double, raining: Bool) {
        let keys: [(Double, Double, Double, Double)] = [
            (0, 0.27, 0.32, 0.58), (5, 0.27, 0.32, 0.58), (6, 1, 0.84, 0.74), (7, 1, 1, 1),
            (15, 1, 1, 1), (16.5, 1, 0.90, 0.70), (17.6, 0.98, 0.62, 0.46), (18.6, 0.52, 0.38, 0.62),
            (20, 0.27, 0.32, 0.58), (24, 0.27, 0.32, 0.58),
        ]
        let h = hour.truncatingRemainder(dividingBy: 24)
        let next = keys.firstIndex { $0.0 > h } ?? keys.count - 1
        let a = keys[max(0, next - 1)], b = keys[next]
        let t = b.0 > a.0 ? (h - a.0) / (b.0 - a.0) : 0
        var red = a.1 + (b.1 - a.1) * t, green = a.2 + (b.2 - a.2) * t, blue = a.3 + (b.3 - a.3) * t
        if raining || stormy {
            let dim = stormy ? 0.55 : 0.82
            red *= dim * 0.92
            green *= dim * 0.97
            blue *= dim
        }
        skyTint.color = NSColor(red: red, green: green, blue: blue, alpha: 1)

        let night = min(1, max(0, (1 - (red + green) / 2) / 0.68))
        fireflies.alpha = raining ? 0 : night
        glow.alpha = fireLit ? 0.25 + 0.6 * night : 0
        rain.isHidden = !(raining || stormy)
    }

    // MARK: The castaway

    /// Walks by keyboard. `canWalk` says whether a map pixel may be stood on.
    func move(dx: CGFloat, dy: CGFloat, seconds: TimeInterval, canWalk: (Int, Int) -> Bool) {
        guard !asleep, dx != 0 || dy != 0 else {
            if hero.action(forKey: "step") != nil {
                hero.removeAction(forKey: "step")
                hero.texture = idleTexture
            }
            return
        }
        let length = hypot(dx, dy)
        let step = CGFloat(seconds) * 95
        var position = hero.position
        // Each axis on its own, so you slide along a shore instead of sticking to it.
        let nextX = position.x + dx / length * step
        if canWalk(Int(nextX.rounded()), Int((mapHeight - position.y).rounded())) { position.x = nextX }
        let nextY = position.y + dy / length * step
        if canWalk(Int(position.x.rounded()), Int((mapHeight - nextY).rounded())) { position.y = nextY }
        hero.position = position
        if dx != 0 { hero.xScale = dx < 0 ? -1 : 1 }
        if hero.action(forKey: "step") == nil {
            hero.run(.repeatForever(.animate(with: stepTextures, timePerFrame: 0.11)), withKey: "step")
        }
    }

    /// The line floating over the castaway: what Space would do here.
    func setPrompt(_ text: String?, enabled: Bool) {
        let key = (text ?? "") + (enabled ? "+" : "-")
        guard key != promptText else { return }
        promptText = key
        prompt.isHidden = text == nil
        guard let text else { return }
        let image = PixelFont.image(text, color: enabled ? 0xfff3a8 : 0xd0d0d0, outline: 0x3b2416)
        prompt.texture = texture(image)
        prompt.size = CGSize(width: image.width, height: image.height)
    }

    /// Gives a tree or rock a little shake while it is being worked on.
    func shake(prop index: Int) {
        let node = propNodes[index]
        let wiggle = SKAction.sequence([.rotate(toAngle: 0.07, duration: 0.09), .rotate(toAngle: -0.07, duration: 0.18), .rotate(toAngle: 0, duration: 0.09)])
        node.run(.repeat(wiggle, count: 5))
    }

    /// 0...1 while busy, nil when free.
    func setProgress(_ value: Double?) {
        progressBack.isHidden = value == nil
        progressFill.isHidden = value == nil
        guard let value else {
            hero.removeAction(forKey: "work")
            // The hop may have been cut off mid-air.
            if let workOrigin, !asleep { hero.position = workOrigin }
            workOrigin = nil
            return
        }
        progressFill.xScale = CGFloat(min(max(value, 0), 1))
        hero.removeAction(forKey: "step")
        if hero.action(forKey: "work") == nil, !asleep {
            hero.texture = idleTexture
            workOrigin = hero.position
            let hop = SKAction.sequence([.moveBy(x: 0, y: 2, duration: 0.14), .moveBy(x: 0, y: -2, duration: 0.14), .wait(forDuration: 0.12)])
            hero.run(.repeatForever(hop), withKey: "work")
        }
    }

    func setAsleep(_ sleeping: Bool) {
        guard sleeping != asleep else { return }
        asleep = sleeping
        hero.removeAllActions()
        hero.xScale = 1
        let image = sleeping ? Art.heroAsleep : Art.heroIdle
        hero.texture = texture(image)
        hero.size = CGSize(width: image.width, height: image.height)
        let bed = IslandMap.bed
        hero.position = sleeping ? point(bed.x + 1, bed.y) : point(bed.x + 10, bed.y + 6)
        hero.zPosition = CGFloat(bed.y) + 1
        zzz.isHidden = !sleeping
        zzz.position = CGPoint(x: hero.position.x + 6, y: hero.position.y + 14)
    }

    func popup(_ texts: [String]) {
        for (index, text) in texts.enumerated() {
            let node = SKSpriteNode(texture: texture(PixelFont.image(text, color: 0xffffff, outline: 0x3b2416)))
            node.position = CGPoint(x: onScreen(hero.position.x, width: node.size.width), y: hero.position.y + 34)
            node.zPosition = 8000
            node.alpha = 0
            node.run(.sequence([
                .wait(forDuration: Double(index) * 0.45),
                .fadeIn(withDuration: 0.1),
                .moveBy(x: 0, y: 16, duration: 1.1),
                .fadeOut(withDuration: 0.3),
                .removeFromParent(),
            ]))
            addChild(node)
        }
    }

    func finish(_ outcome: Outcome) {
        setProgress(nil)
        switch outcome {
        case .rescued:
            signalFire.isHidden = false
            ship.isHidden = false
            let lane = mapHeight - 30
            ship.position = CGPoint(x: CGFloat(IslandMap.peak.x) + 320, y: lane)
            ship.run(.move(to: CGPoint(x: CGFloat(IslandMap.peak.x) + 110, y: lane), duration: 6), withKey: "sail")
        case .storm:
            stormy = true
        case .died:
            setAsleep(false)
            hero.zRotation = .pi / 2
        }
    }

    // MARK: Camera and time

    /// Keeps the castaway in view without showing past the edge of the world.
    private func follow() {
        guard !mapOpen else { return }
        eye.position = CGPoint(
            x: min(max(hero.position.x, size.width / 2), mapWidth - size.width / 2).rounded(),
            y: min(max(hero.position.y, size.height / 2), mapHeight - size.height / 2).rounded())
    }

    /// Pulls the camera back until the whole island fits, or drops back down to the castaway.
    func setMap(_ open: Bool) {
        guard open != mapOpen else { return }
        mapOpen = open
        let zoom = CGFloat(IslandMap.scale)
        let seconds = 0.45
        let move: SKAction
        if open {
            move = .group([.scale(to: zoom, duration: seconds), .move(to: CGPoint(x: mapWidth / 2, y: mapHeight / 2), duration: seconds)])
        } else {
            let home = CGPoint(
                x: min(max(hero.position.x, size.width / 2), mapWidth - size.width / 2).rounded(),
                y: min(max(hero.position.y, size.height / 2), mapHeight - size.height / 2).rounded())
            move = .group([.scale(to: 1, duration: seconds), .move(to: home, duration: seconds)])
        }
        move.timingMode = .easeInEaseOut
        eye.run(move, withKey: "zoom")
        mapLayer.run(.fadeAlpha(to: open ? 1 : 0, duration: seconds))
        // So you can find yourself from up there.
        hero.run(.scale(to: open ? zoom * 0.7 : 1, duration: seconds), withKey: "grow")
        hero.zPosition = open ? 6950 : mapHeight - hero.position.y
        prompt.alpha = open ? 0 : 1
    }

    /// An x that keeps something `width` wide fully on screen.
    private func onScreen(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let reach = size.width / 2 - width / 2 - 2
        return min(max(x, eye.position.x - reach), eye.position.x + reach)
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = min(0.1, currentTime - (lastUpdate ?? currentTime))
        lastUpdate = currentTime
        if !asleep, !mapOpen { hero.zPosition = mapHeight - hero.position.y }
        progressBack.position = CGPoint(x: hero.position.x, y: hero.position.y + 20)
        progressFill.position = CGPoint(x: hero.position.x - 8, y: hero.position.y + 20)
        prompt.position = CGPoint(x: onScreen(hero.position.x, width: prompt.size.width), y: hero.position.y + 18)
        follow()
        onTick?(delta)
    }
}
