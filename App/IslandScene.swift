import IslandCore
import SpriteKit
import SwiftUI

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
    private var shown: Prompt?
    private struct Square: Hashable {
        let x, y: Int
    }

    /// The ground near the camera, with what grows on it. The rest of the island is not drawn.
    private var squares: [Square: SKNode] = [:]
    private var known: Set<Region> = []
    private var propNodes: [IslandMap.Prop.ID: SKSpriteNode] = [:]
    /// Things already gathered and not grown back yet.
    private var spent: Set<IslandMap.Prop.ID> = []
    private var giants: [IslandMap.Prop.ID: SKSpriteNode] = [:]
    private let overview = SKSpriteNode()
    private let painter = DispatchQueue(label: "island.painter", qos: .userInitiated)
    private let fire = SKSpriteNode()
    private let glow = SKSpriteNode()
    private let signalFire = SKSpriteNode()
    private let ship = SKSpriteNode()
    private let skyTint = SKSpriteNode(color: .white, size: .zero)
    private let rain = SKNode()
    private let fireflies = SKNode()
    private var labels: [Region: (name: SKSpriteNode, unknown: SKSpriteNode)] = [:]
    private let mapLayer = SKNode()
    private var mapOpen = false
    /// How far the camera pulls back to fit the whole island.
    private let zoom = CGFloat(IslandMap.width) / CGFloat(IslandMap.viewWidth)
    private var built: [Structure: SKSpriteNode] = [:]

    private var fireLit = false
    private var stormy = false
    private var asleep = false

    /// Which way the castaway is turned. Left is `side` mirrored.
    private enum Facing { case front, back, side }
    private var facing = Facing.front

    private lazy var idleTexture = texture(Art.heroIdle)
    private lazy var standing: [Facing: SKTexture] = [
        .front: idleTexture, .back: texture(Art.heroBackIdle), .side: texture(Art.heroSideIdle),
    ]
    private lazy var walking: [Facing: [SKTexture]] = [
        .front: [texture(Art.heroStepA), texture(Art.heroStepB)],
        .back: [texture(Art.heroBackStepA), texture(Art.heroBackStepB)],
        .side: [texture(Art.heroSideStepA), texture(Art.heroSideIdle), texture(Art.heroSideStepB), texture(Art.heroSideIdle)],
    ]
    private lazy var fireTextures = [texture(Art.fireA), texture(Art.fireB)]

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = NSColor(red: 0.247, green: 0.498, blue: 0.682, alpha: 1)
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

    /// Sprites drawn many times over share one texture.
    private var shared: [CGImage: SKTexture] = [:]
    private func stamp(_ image: CGImage) -> SKTexture {
        if let made = shared[image] { return made }
        let made = texture(image)
        shared[image] = made
        return made
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
        node.texture = stamp(image)
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
        addChild(eye)
        camera = eye

        var seed: UInt64 = 99
        func roll() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }

        overview.size = CGSize(width: mapWidth, height: mapHeight)
        overview.position = CGPoint(x: mapWidth / 2, y: mapHeight / 2)
        overview.zPosition = 26800
        overview.alpha = 0
        addChild(overview)

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
        prompt.zPosition = 26600
        prompt.isHidden = true
        addChild(prompt)

        zzz.texture = texture(Art.zzz)
        zzz.size = CGSize(width: Art.zzz.width, height: Art.zzz.height)
        zzz.zPosition = 25500
        addChild(zzz)
        bob(zzz, by: 3, every: 0.8)

        progressBack.zPosition = 26500
        progressFill.zPosition = 26501
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        addChild(progressBack)
        addChild(progressFill)

        // What each region holds, and question marks, only on the zoomed-out map.
        mapLayer.zPosition = 26900
        mapLayer.alpha = 0
        addChild(mapLayer)
        for region in Region.allCases {
            let yields = Item.allCases.filter { region.yields.base(for: $0) > 0 }.map(Art.icon)
            let name = SKSpriteNode(texture: texture(Bitmap.plate([Art.icon(region)] + yields)))
            let unknown = SKSpriteNode(texture: texture(Art.question))
            name.setScale(zoom)
            unknown.setScale(zoom * 2)
            name.position = spot(region)
            unknown.position = spot(region)
            labels[region] = (name, unknown)
            mapLayer.addChild(name)
            mapLayer.addChild(unknown)
        }

        // Light
        skyTint.size = CGSize(width: size.width + 4, height: size.height + 4)
        skyTint.zPosition = 27000
        skyTint.blendMode = .multiply
        eye.addChild(skyTint)

        glow.texture = texture(Self.glowImage)
        glow.size = CGSize(width: 72, height: 72)
        glow.position = CGPoint(x: fire.position.x, y: fire.position.y + 4)
        glow.zPosition = 27100
        glow.blendMode = .add
        addChild(glow)
        glow.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 0.3), .scale(to: 0.97, duration: 0.25)])))

        fireflies.zPosition = 27200
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

        rain.zPosition = 27300
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
        ship.zPosition = 24000
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
        facing = .front
        hero.texture = idleTexture
        hero.size = idleTexture.size()
        hero.position = point(IslandMap.start.x, IslandMap.start.y)
        workOrigin = nil
        follow()
        zzz.isHidden = true
        setPrompt(nil)
        point(at: nil)
        ship.removeAction(forKey: "sail")
        ship.isHidden = true
        giants.values.forEach { $0.alpha = 1 }
        signalFire.isHidden = true
        setProgress(nil)
    }

    func sync(state: GameState) {
        for region in Region.allCases {
            let known = state.discovered.contains(region)
            labels[region]?.name.isHidden = !known
            labels[region]?.unknown.isHidden = known
        }
        if state.discovered != known {
            known = state.discovered
            // The clouds lift: repaint the ground in view, and the map.
            if squares.isEmpty { tend(now: true) } else { squares.keys.forEach { paint($0) } }
            propNodes.values.forEach(show)
            let mask = IslandMap.mask(known), step = Int(zoom / 2)
            painter.async { [weak self] in
                let image = IslandMap.overview(known: mask, step: step)
                DispatchQueue.main.async {
                    guard let self, mask == IslandMap.mask(self.known) else { return }
                    self.overview.texture = self.texture(image)
                }
            }
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
                hero.texture = standing[facing]
            }
            return
        }
        let length = hypot(dx, dy)
        let step = CGFloat(seconds) * 120
        var position = hero.position
        // Each axis on its own, so you slide along a shore instead of sticking to it.
        let nextX = position.x + dx / length * step
        if canWalk(Int(nextX.rounded()), Int((mapHeight - position.y).rounded())) { position.x = nextX }
        let nextY = position.y + dy / length * step
        if canWalk(Int(position.x.rounded()), Int((mapHeight - nextY).rounded())) { position.y = nextY }
        hero.position = position
        if dx != 0 { hero.xScale = dx < 0 ? -1 : 1 }
        let turned: Facing = dx != 0 ? .side : dy > 0 ? .back : .front
        if hero.action(forKey: "step") == nil || turned != facing {
            facing = turned
            hero.run(.repeatForever(.animate(with: walking[facing]!, timePerFrame: facing == .side ? 0.09 : 0.11)), withKey: "step")
        }
    }

    /// The bubble floating over the castaway: what Space would do here.
    func setPrompt(_ next: Prompt?) {
        guard next != shown else { return }
        shown = next
        prompt.isHidden = next == nil
        guard let next else { return point(at: nil) }
        let image = Bitmap.plate(next.icons, face: next.enabled ? Ink.panel : 0xc9c0b6)
        prompt.texture = texture(image)
        prompt.size = CGSize(width: image.width, height: image.height)
    }

    // MARK: Things you can touch

    private func picture(of kind: IslandMap.Kind, _ id: IslandMap.Prop.ID) -> CGImage {
        let pick = abs(id.cellX &+ id.cellY &* 3)
        switch kind {
        case .palm: return (spent.contains(id) ? Art.barePalms : Art.palms)[pick % Art.palms.count]
        case .tree: return Art.trees[pick % Art.trees.count]
        case .snag: return Art.snags[pick % Art.snags.count]
        case .bush: return Art.bush
        case .rock: return Art.rock
        case .fern: return Art.fern
        case .shell: return Art.shell
        case .driftwood: return Art.driftwood
        }
    }

    /// Shows a thing as it is now: hidden under cloud, carried off, or stripped.
    private func show(_ sprite: SKSpriteNode) {
        guard let id = sprite.userData?["id"] as? IslandMap.Prop.ID, let kind = sprite.userData?["kind"] as? IslandMap.Kind,
              let region = sprite.userData?["region"] as? Region else { return }
        sprite.isHidden = !known.contains(region) || (spent.contains(id) && kind.isCarriedOff)
        sprite.texture = stamp(picture(of: kind, id))
        sprite.setScale(1)
        sprite.alpha = 1
    }

    /// What has been gathered and has not grown back. Anything else is whole again.
    func setSpent(_ ids: Set<IslandMap.Prop.ID>) {
        let changed = spent.symmetricDifference(ids)
        spent = ids
        for id in changed { propNodes[id].map(show) }
    }

    /// Turns the castaway to the thing and works at it, blow after blow, until `setProgress(nil)`.
    func work(on id: IslandMap.Prop.ID, hit: @escaping () -> Void) {
        guard let node = propNodes[id], let kind = node.userData?["kind"] as? IslandMap.Kind else { return }
        let dx = node.position.x - hero.position.x, dy = node.position.y - hero.position.y
        facing = abs(dx) > abs(dy) * 0.6 ? .side : dy > 0 ? .back : .front
        if facing == .side { hero.xScale = dx < 0 ? -1 : 1 }
        // A giant barely stirs.
        let sway: CGFloat = id.tall ? 0.012 : 0.09
        let chips: [UInt32] = switch kind {
        case .palm, .bush, .fern: [0x6f9f48, 0x487f3f]
        case .tree, .driftwood: [0xa87a48, 0x86592f]
        case .snag: [0xa89d92, 0xd6cec4]
        case .rock: [0x9a8f85, 0xc9c0b6]
        case .shell: [0xf29bb0, 0xffffff]
        }
        let blow = SKAction.run { [weak self, weak node] in
            guard let self, let node else { return }
            hit()
            // Where the hands are: low on a giant, right on a small thing.
            let at = CGPoint(x: node.position.x + (id.tall ? (dx < 0 ? 6 : -6) : 0), y: node.position.y + (id.tall ? 10 : 3))
            for index in 0..<4 {
                let chip = SKSpriteNode(color: NSColor(Color(hex: chips[index % 2])), size: CGSize(width: index % 2 + 1, height: 1))
                chip.position = at
                chip.zPosition = node.zPosition + 1
                let out = CGFloat(index) * 5 - 7.5 + CGFloat.random(in: -2...2)
                let arc = SKAction.sequence([.moveBy(x: out * 0.5, y: 7, duration: 0.14), .moveBy(x: out * 0.5, y: -9, duration: 0.2)])
                chip.run(.sequence([.group([arc, .sequence([.wait(forDuration: 0.22), .fadeOut(withDuration: 0.12)])]), .removeFromParent()]))
                self.addChild(chip)
            }
        }
        let wiggle = SKAction.sequence([.rotate(toAngle: sway, duration: 0.06), .rotate(toAngle: -sway, duration: 0.1), .rotate(toAngle: 0, duration: 0.06)])
        node.run(.repeatForever(.sequence([blow, wiggle, .wait(forDuration: 0.3)])), withKey: "worked")
        worked = node
    }

    /// The work paid off: small things are carried away, a palm drops its coconuts.
    func collect(_ id: IslandMap.Prop.ID) {
        spent.insert(id)
        guard let node = propNodes[id], let kind = node.userData?["kind"] as? IslandMap.Kind else { return }
        if kind.isCarriedOff {
            node.run(.sequence([.group([.scale(to: 0.3, duration: 0.18), .moveBy(x: 0, y: 6, duration: 0.18), .fadeOut(withDuration: 0.18)]),
                                .run { [weak self, weak node] in node.map { $0.position.y -= 6; self?.show($0) } }]))
        } else if kind == .palm {
            show(node)
            for index in 0..<3 {
                let nut = SKSpriteNode(texture: stamp(Art.coconut))
                nut.position = CGPoint(x: node.position.x + CGFloat(index * 6 - 2), y: node.position.y + 96)
                nut.zPosition = node.zPosition + 2
                let fall = SKAction.moveBy(x: CGFloat(index * 5 - 5), y: -92, duration: 0.42)
                fall.timingMode = .easeIn
                let bounce = SKAction.sequence([.moveBy(x: 2, y: 7, duration: 0.1), .moveBy(x: 2, y: -7, duration: 0.1)])
                nut.run(.sequence([.wait(forDuration: Double(index) * 0.12), fall, bounce, .wait(forDuration: 0.5), .fadeOut(withDuration: 0.3), .removeFromParent()]))
                addChild(nut)
            }
        }
    }

    private weak var worked: SKNode?

    private lazy var pointer: SKSpriteNode = {
        let pointer = SKSpriteNode(texture: stamp(Art.pointer))
        pointer.zPosition = 26550
        pointer.isHidden = true
        addChild(pointer)
        bob(pointer, by: 2, every: 0.35)
        return pointer
    }()
    private var pointed: IslandMap.Prop.ID?

    /// Hovers an arrow over the thing Space would use, so it is clear which one is meant.
    func point(at id: IslandMap.Prop.ID?) {
        guard id != pointed else { return }
        pointed = id
        guard let id, let node = propNodes[id] else {
            pointer.isHidden = true
            return
        }
        pointer.removeAllActions()
        // On a giant the arrow marks the trunk, not the faraway crown.
        pointer.position = CGPoint(x: node.position.x, y: node.position.y + (id.tall ? 44 : node.size.height + 6))
        pointer.isHidden = false
        bob(pointer, by: 2, every: 0.35)
    }

    /// 0...1 while busy, nil when free.
    func setProgress(_ value: Double?) {
        progressBack.isHidden = value == nil
        progressFill.isHidden = value == nil
        guard let value else {
            hero.removeAction(forKey: "work")
            worked?.removeAction(forKey: "worked")
            worked?.zRotation = 0
            worked = nil
            // The hop may have been cut off mid-air.
            if let workOrigin, !asleep { hero.position = workOrigin }
            workOrigin = nil
            return
        }
        progressFill.xScale = CGFloat(min(max(value, 0), 1))
        hero.removeAction(forKey: "step")
        if hero.action(forKey: "work") == nil, !asleep {
            // Keep facing whatever is being worked on.
            hero.texture = standing[facing]
            workOrigin = hero.position
            let hop = SKAction.sequence([.moveBy(x: 0, y: 2, duration: 0.14), .moveBy(x: 0, y: -2, duration: 0.14), .wait(forDuration: 0.12)])
            hero.run(.repeatForever(hop), withKey: "work")
        }
    }

    func setAsleep(_ sleeping: Bool) {
        guard sleeping != asleep else { return }
        asleep = sleeping
        facing = .front
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

    /// Floats what just happened up from the castaway, one row of pictures at a time.
    func popup(_ rows: [[CGImage]]) {
        for (index, row) in rows.enumerated() {
            let node = SKSpriteNode(texture: texture(Bitmap.plate(row, face: 0xfff3d6)))
            node.position = CGPoint(x: onScreen(hero.position.x, width: node.size.width), y: hero.position.y + 34)
            node.zPosition = 28000
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
            // Seen from high up: the ship comes in across the northern sea.
            setMap(true)
            ship.setScale(zoom)
            let lane = mapHeight * 0.96
            ship.position = CGPoint(x: mapWidth * 1.02, y: lane)
            ship.run(.move(to: CGPoint(x: CGFloat(IslandMap.peak.x) + mapWidth * 0.12, y: lane), duration: 6), withKey: "sail")
        case .storm:
            stormy = true
        case .died:
            setAsleep(false)
            hero.zRotation = .pi / 2
        }
    }

    // MARK: The ground underfoot

    /// Draws the squares around the camera and lets go of the ones left behind.
    private func tend(now: Bool = false) {
        guard !mapOpen, eye.xScale == 1 else { return }
        let side = CGFloat(IslandMap.chunk), reach = side / 2
        let columns = Int(((eye.position.x - size.width / 2 - reach) / side).rounded(.down))...Int(((eye.position.x + size.width / 2 + reach) / side).rounded(.down))
        // Map rows run downward; scene y runs upward.
        let top = mapHeight - eye.position.y
        let rows = Int(((top - size.height / 2 - reach) / side).rounded(.down))...Int(((top + size.height / 2 + reach + 160) / side).rounded(.down))
        for row in rows {
            for column in columns where squares[Square(x: column, y: row)] == nil {
                plant(Square(x: column, y: row), now: now)
            }
        }
        for (square, node) in squares
        where square.x < columns.lowerBound - 1 || square.x > columns.upperBound + 1 || square.y < rows.lowerBound - 1 || square.y > rows.upperBound + 1 {
            for case let sprite as SKSpriteNode in node.children {
                guard let id = sprite.userData?["id"] as? IslandMap.Prop.ID else { continue }
                propNodes[id] = nil
                giants[id] = nil
            }
            node.removeFromParent()
            squares[square] = nil
        }
    }

    /// A new square: what grows there right away, the painted ground as soon as it is ready.
    private func plant(_ square: Square, now: Bool) {
        let node = SKNode()
        squares[square] = node
        addChild(node)
        for prop in IslandMap.props(chunkX: square.x, chunkY: square.y) {
            let sprite = SKSpriteNode()
            node.addChild(sprite)
            place(sprite, picture(of: prop.kind, prop.id), x: prop.x, y: prop.y)
            sprite.userData = ["id": prop.id, "region": prop.region, "kind": prop.kind]
            show(sprite)
            propNodes[prop.id] = sprite
            if prop.kind.isTall {
                giants[prop.id] = sprite
                let shade = SKSpriteNode(texture: stamp(Art.shade))
                shade.alpha = 0.22
                shade.position = CGPoint(x: 6, y: 2)
                shade.zPosition = -CGFloat(prop.y) - 400
                sprite.addChild(shade)
            }
        }
        // A few waves that come and go, where this square is open sea.
        var seed = UInt64(truncatingIfNeeded: square.x &* 73_856_093 ^ square.y &* 19_349_663)
        func roll() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        for _ in 0..<10 {
            let x = square.x * IslandMap.chunk + Int(roll() * Double(IslandMap.chunk))
            let y = square.y * IslandMap.chunk + Int(roll() * Double(IslandMap.chunk))
            let wait = roll() * 4, pause = 1 + roll() * 3
            guard IslandMap.shore(x, y) > 1.04 else { continue }
            let wave = SKSpriteNode(texture: stamp(Art.wave))
            wave.position = point(x, y)
            wave.zPosition = -900
            wave.alpha = 0
            let drift = SKAction.group([
                .sequence([.fadeAlpha(to: 0.9, duration: 1.2), .fadeOut(withDuration: 1.2)]),
                .moveBy(x: -5, y: 0, duration: 2.4),
            ])
            wave.run(.sequence([
                .wait(forDuration: wait),
                .repeatForever(.sequence([drift, .moveBy(x: 5, y: 0, duration: 0), .wait(forDuration: pause)])),
            ]))
            node.addChild(wave)
        }
        paint(square, now: now)
    }

    /// Paints a square's ground off the main thread and fades it in over whatever was there.
    private func paint(_ square: Square, now: Bool = false) {
        let mask = IslandMap.mask(known)
        func lay(_ image: CGImage) {
            guard let node = squares[square] else { return }
            // The clouds may have lifted while this was being painted.
            guard mask == IslandMap.mask(known) else { return paint(square) }
            let old = node.children.filter { $0.name == "ground" }
            let ground = SKSpriteNode(texture: texture(image))
            ground.name = "ground"
            let half = IslandMap.chunk / 2
            ground.position = point(square.x * IslandMap.chunk + half, square.y * IslandMap.chunk + half)
            ground.zPosition = -1000
            node.addChild(ground)
            if !old.isEmpty {
                ground.alpha = 0
                ground.run(.sequence([.fadeIn(withDuration: 0.9), .run { old.forEach { $0.removeFromParent() } }]))
            }
        }
        if now {
            lay(IslandMap.terrain(chunkX: square.x, chunkY: square.y, known: mask))
        } else {
            painter.async {
                let image = IslandMap.terrain(chunkX: square.x, chunkY: square.y, known: mask)
                DispatchQueue.main.async { lay(image) }
            }
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
        overview.run(.fadeAlpha(to: open ? 1 : 0, duration: seconds))
        // So you can find yourself from up there.
        hero.run(.scale(to: open ? zoom * 1.2 : 1, duration: seconds), withKey: "grow")
        hero.zPosition = open ? 26950 : mapHeight - hero.position.y
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
        // Grass and brush stir as you push past.
        if hero.action(forKey: "step") != nil {
            for (id, node) in propNodes where !id.tall && !node.isHidden && node.action(forKey: "brushed") == nil
                && abs(node.position.x - hero.position.x) < 8 && abs(node.position.y - hero.position.y) < 6 {
                guard let kind = node.userData?["kind"] as? IslandMap.Kind, kind == .fern || kind == .bush else { continue }
                let lean: CGFloat = node.position.x < hero.position.x ? 0.16 : -0.16
                node.run(.sequence([.rotate(toAngle: lean, duration: 0.08), .rotate(toAngle: -lean * 0.5, duration: 0.14), .rotate(toAngle: 0, duration: 0.1)]), withKey: "brushed")
            }
        }
        // Walk behind a giant and it turns to glass, so you never lose yourself.
        for giant in giants.values where !giant.isHidden {
            let behind = !mapOpen && hero.position.y > giant.position.y && hero.position.y < giant.position.y + giant.size.height - 8
                && abs(hero.position.x - giant.position.x) < giant.size.width / 2 - 6
            let target: CGFloat = behind ? 0.35 : 1
            if giant.alpha != target {
                let next = giant.alpha + (target - giant.alpha) * min(1, CGFloat(delta) * 9)
                giant.alpha = abs(next - target) < 0.02 ? target : next
            }
        }
        progressBack.position = CGPoint(x: hero.position.x, y: hero.position.y + 20)
        progressFill.position = CGPoint(x: hero.position.x - 8, y: hero.position.y + 20)
        prompt.position = CGPoint(x: onScreen(hero.position.x, width: prompt.size.width), y: hero.position.y + 18)
        follow()
        tend()
        onTick?(delta)
    }
}
