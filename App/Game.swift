import AppKit
import IslandCore

/// What Space would do where the castaway stands.
struct Prompt: Equatable {
    let action: Action
    let hours: Int
    /// What is in the way, if Space would do nothing.
    let blocker: Blocker?

    enum Blocker: Equatable {
        case level(Int), tool(Structure), noPath, rescueList, wood, daylight
    }

    var enabled: Bool { blocker == nil }

    /// The prompt as pictures: the key and what it does, or the thing and what it still needs.
    var icons: [CGImage] {
        switch blocker {
        case nil: [Art.spaceKey, action.icon] + (hours > 0 ? [Art.hourglass, Art.number(hours)] : [])
        case let .level(level): [action.icon, Art.cross, Art.icon(Skill.exploration), Art.up, Art.number(level)]
        case let .tool(tool): [action.icon, Art.cross, Art.picture(tool)]
        case .noPath: [action.icon, Art.cross]
        case .rescueList: [action.icon, Art.cross, Art.todo]
        case .wood: [action.icon, Art.cross, Art.log]
        case .daylight: [action.icon, Art.cross, Art.hourglass]
        }
    }
}

/// Runs `GameEngine` in real time: you walk the island yourself, hours pass on their own,
/// work takes a while, night follows day. The rules stay in the engine. An idle hour is the
/// engine's `.rest`: thirst, hunger, a little energy, and the sun if you spend it in the open.
final class Game: ObservableObject {
    @Published private(set) var engine: GameEngine
    @Published private(set) var journal: Journal
    @Published private(set) var here: Region = .beach
    /// Which square of the chart the castaway stands in, like "C4".
    @Published private(set) var cell = ""
    @Published private(set) var prompt: Prompt?
    @Published private(set) var working: Action?
    @Published private(set) var sleeping = false
    @Published private(set) var isNight = false
    @Published private(set) var saveError: String?
    @Published var crafting = false
    @Published var paused = false
    /// The opening is still playing: nothing ticks and any key skips it.
    @Published var intro = true

    @Published var mapOpen = false {
        didSet { scene.setMap(mapOpen) }
    }

    let scene = IslandScene(size: CGSize(width: IslandMap.viewWidth, height: IslandMap.viewHeight))

    private enum Phase {
        case idle
        case working(Action, from: Double, elapsed: Double, duration: Double)
        case dusk(from: Double, elapsed: Double)
        case dawn(to: Double, elapsed: Double)
        case over
    }

    private enum Key {
        static let left: Set<UInt16> = [123, 0], right: Set<UInt16> = [124, 2]
        static let down: Set<UInt16> = [125, 1], up: Set<UInt16> = [126, 13]
        static let act: Set<UInt16> = [49, 14, 36]
        static let craft: UInt16 = 8, pause: UInt16 = 35, escape: UInt16 = 53, map: UInt16 = 46
        static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    /// Real seconds for one game hour while nothing is happening.
    private let secondsPerHour = 15.0
    private let nightSeconds = 4.0
    private let dayEnd = 18.0

    private var phase = Phase.idle
    /// How far into the current idle hour we are, 0..<1.
    private var idle = 0.0
    private var clock = 6.0
    private var held: Set<UInt16> = []
    private var nearProp: IslandMap.Prop.ID?
    /// How long the castaway has stood still; long enough, and a thought comes.
    private var still = 0.0
    /// The thing being worked on right now.
    private var inHand: IslandMap.Prop.ID?
    /// What has been gathered, and on which day. It comes back after a while:
    /// new wood washes ashore, coconuts ripen.
    private var spent: [IslandMap.Prop.ID: Int] = [:]
    private let regrowDays = 3
    private let journalURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".island/journal.json")

    init() {
        let journal = Journal.load(from: journalURL)
        self.journal = journal
        engine = GameEngine(seed: .random(in: 1...UInt64.max), journal: journal)
        scene.onTick = { [weak self] in self?.tick($0) }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, !event.modifierFlags.contains(.command) else { return event }
            return press(event.keyCode, down: event.type == .keyDown, repeated: event.isARepeat) ? nil : event
        }
        scene.lost = journal.runs - journal.rescues
        refresh()
        scene.playIntro { [weak self] in self?.intro = false }
    }

    var isBusy: Bool { working != nil || sleeping }

    /// Recipes still worth showing in the craft menu.
    var recipes: [Recipe] {
        Recipe.allCases.filter { recipe in
            if case let .structure(structure) = recipe.spec.output { return !engine.state.has(structure) }
            return true
        }
    }

    /// Crafting follows the engine, plus being where the thing gets built.
    func canCraft(_ recipe: Recipe) -> Bool {
        engine.canPerform(.craft(recipe)) && (recipe.spec.requiresRegion ?? here) == here
    }

    // MARK: What the player does

    private func press(_ key: UInt16, down: Bool, repeated: Bool) -> Bool {
        if intro {
            if down, !repeated { scene.skipIntro() }
            return true
        }
        let moves = Key.left.union(Key.right).union(Key.up).union(Key.down)
        if moves.contains(key) {
            if down { held.insert(key) } else { held.remove(key) }
            return true
        }
        guard down else { return Key.act.contains(key) }
        guard !repeated else { return true }

        if engine.state.isOver {
            if Key.act.contains(key) { restart() }
            return true
        }
        switch key {
        case Key.pause:
            paused.toggle()
        case Key.escape:
            if crafting || mapOpen {
                crafting = false
                mapOpen = false
            } else {
                paused.toggle()
            }
        case Key.map:
            toggleMap()
        case Key.craft:
            toggleCrafting()
        case _ where Key.act.contains(key):
            if paused {
                paused = false
            } else if mapOpen {
                mapOpen = false
            } else if !crafting, let prompt {
                if prompt.enabled { begin(prompt.action) } else { Sound.shared.play(.blocked) }
            }
        case _ where crafting && Key.digits.contains(key):
            let index = Key.digits.firstIndex(of: key)!
            if recipes.indices.contains(index) { craft(recipes[index]) }
        default:
            return false
        }
        return true
    }

    func toggleCrafting() {
        guard case .idle = phase, !paused, !engine.state.isOver else { return }
        mapOpen = false
        crafting.toggle()
        Sound.shared.play(.tick)
    }

    func toggleMap() {
        guard !engine.state.isOver else { return }
        // No map until you have drawn one.
        guard engine.state.has(.map) else {
            Sound.shared.play(.blocked)
            scene.think([Art.mapIcon, Art.cross, Art.key("C")], toward: nil)
            return
        }
        crafting = false
        mapOpen.toggle()
        Sound.shared.play(.tick)
    }

    func craft(_ recipe: Recipe) {
        guard canCraft(recipe) else { return }
        crafting = false
        begin(.craft(recipe))
    }

    private func begin(_ action: Action) {
        guard case .idle = phase, !paused, engine.canPerform(action) else { return }
        if case .sleep = action {
            startNight()
            return
        }
        inHand = nil
        var motion = IslandScene.Motion.strike
        switch action {
        case .gather:
            inHand = nearProp
            let kind = IslandMap.props(around: scene.heroSpot.x, scene.heroSpot.y, reach: 40).first { $0.id == nearProp }?.kind
            motion = kind == .palm ? .climb : kind?.isCarriedOff == true ? .pick : .strike
        case .fish: motion = .cast
        case .fetchWater, .makeFire, .lightSignal: motion = .kneel
        case .explore: motion = .search
        default: break
        }
        scene.startWork(motion, on: inHand, axe: engine.state.has(.stoneAxe)) { Sound.shared.play(.work) }
        working = action
        still = 0
        scene.stopThinking()
        scene.setPrompt(nil)
        scene.point(at: nil)
        phase = .working(action, from: clock, elapsed: 0, duration: 0.9 + Double(engine.hours(for: action)) * 0.8)
    }

    func restart() {
        saveError = nil
        engine = GameEngine(seed: .random(in: 1...UInt64.max), journal: journal)
        scene.lost = journal.runs - journal.rescues
        phase = .idle
        idle = 0
        working = nil
        sleeping = false
        crafting = false
        mapOpen = false
        spent = [:]
        scene.setSpent([])
        scene.reset()
        refresh()
    }

    // MARK: Looking around

    private func canWalk(_ x: Int, _ y: Int) -> Bool {
        guard let region = IslandMap.region(x: x, y: y) else { return false }
        guard IslandMap.depth(x, y) > 9, engine.state.discovered.contains(region), !IslandMap.blocked(x, y), !IslandMap.walled(x, y) else { return false }
        // Rocks, brush and driftwood are in the way until they are carried off.
        return !IslandMap.props(around: x, y, reach: 6).contains { prop in
            prop.kind.isSolid && spent[prop.id] == nil && hypot(Double(x - prop.x), Double(y - prop.y + 2)) < 5
        }
    }

    /// The closest thing worth doing from where the castaway stands.
    private func look() {
        let spot = scene.heroSpot
        let state = engine.state
        func distance(_ x: Int, _ y: Int) -> Double { hypot(Double(spot.x - x), Double(spot.y - y)) }
        if let region = IslandMap.region(x: spot.x, y: spot.y), region != here { here = region }
        let name = IslandMap.cellName(x: spot.x, y: spot.y)
        if name != cell { cell = name }

        var found: Action?
        nearProp = nil
        if distance(IslandMap.bed.x, IslandMap.bed.y) < 18 {
            found = .sleep
        } else if distance(IslandMap.fire.x, IslandMap.fire.y) < 18, !state.fireLitToday {
            found = .makeFire
        } else if distance(IslandMap.signal.x, IslandMap.signal.y) < 20 {
            found = .lightSignal
        } else {
            // An arm's reach and a step.
            var best = 22.0
            for prop in IslandMap.props(around: spot.x, spot.y, reach: 34) {
                let item = prop.kind.item
                guard prop.region.yields.base(for: item) > 0, spent[prop.id] == nil,
                      state.discovered.contains(prop.region) else { continue }
                // A giant's trunk keeps you at arm's length.
                let d = distance(prop.x, prop.y - 2) - (prop.kind.isTall ? 14 : 0)
                if d < best {
                    best = d
                    nearProp = prop.id
                    found = .gather(item, prop.region)
                }
            }
        }
        if found == nil, state.discovered.contains(.stream), IslandMap.streamDistance(spot.x, spot.y) < 34 {
            found = .fetchWater
        }
        if found == nil {
            // Fog within reach means land to explore.
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                let x = spot.x + Int((cos(angle) * 14).rounded()), y = spot.y + Int((sin(angle) * 14).rounded())
                if let region = IslandMap.region(x: x, y: y), !state.discovered.contains(region) {
                    found = .explore(region)
                    break
                }
            }
        }
        if found == nil, here == .beach, IslandMap.depth(spot.x, spot.y) < 60 {
            found = .fish
        }

        let next = found.map { action in
            Prompt(action: action, hours: action == .sleep ? 0 : engine.hours(for: action),
                   blocker: engine.canPerform(action) ? nil : blocker(action))
        }
        if next != prompt { prompt = next }
        scene.setPrompt(next)
        scene.point(at: nearProp)
    }

    /// Why an action is locked right now.
    private func blocker(_ action: Action) -> Prompt.Blocker {
        let state = engine.state
        switch action {
        case let .explore(region):
            if let tool = region.requiredTool, !state.has(tool) { return .tool(tool) }
            if engine.level(.exploration) < region.requiredLevel { return .level(region.requiredLevel) }
            if !state.discovered.contains(where: { $0.neighbors.contains(region) }) { return .noPath }
        case .lightSignal:
            return .rescueList
        case .makeFire:
            if state.count(.wood) + state.count(.dryWood) == 0 { return .wood }
        default:
            break
        }
        return .daylight
    }

    /// What the castaway drank since `before`, and whether it sat badly.
    private func sips(since before: GameState) -> [[CGImage]] {
        var notes: [[CGImage]] = []
        for item in [Item.cleanWater, .water] {
            let drunk = before.count(item) - engine.state.count(item)
            // Boiling moves raw water to clean; that is not drinking.
            if drunk > 0, engine.state.needs.thirst > before.needs.thirst { notes.append([Art.icon(item), PixelFont.image("-\(drunk)")]) }
        }
        if engine.state.needs.health < before.needs.health, before.water > engine.state.water { notes.append([Art.murkyDrop, Art.heart, Art.cross]) }
        // Collapsed in the sun.
        if engine.state.needs.temperature >= 75, engine.state.needs.health <= before.needs.health - engine.balance.heatstrokeDamage {
            notes.append([Art.sun, Art.thermometer, Art.cross])
        }
        return notes
    }

    // MARK: Sun and shade

    /// A living giant close enough that the castaway stands in the pool of shade at its foot.
    private func shadeTree(reach: Int) -> [IslandMap.Prop] {
        let spot = scene.heroSpot
        return IslandMap.props(around: spot.x, spot.y, reach: reach).filter { $0.kind == .palm || $0.kind == .tree }
    }

    /// Under trees, or in the shadow of one, or under your own roof.
    private func inShade() -> Bool {
        if !here.isOpenSky { return true }
        let spot = scene.heroSpot
        if engine.state.has(.shelter), hypot(Double(spot.x - IslandMap.bed.x), Double(spot.y - IslandMap.bed.y)) < 24 { return true }
        return shadeTree(reach: 44).contains { abs(spot.x - $0.x - 6) < 38 && abs(spot.y - $0.y) < 14 }
    }

    private func nearestShade() -> (x: Int, y: Int)? {
        let spot = scene.heroSpot
        return shadeTree(reach: 700)
            .min { hypot(Double($0.x - spot.x), Double($0.y - spot.y)) < hypot(Double($1.x - spot.x), Double($1.y - spot.y)) }
            .map { ($0.x + 14, $0.y + 4) }
    }

    // MARK: Nudges

    /// The nearest thing of a kind that is still there to gather, within a long walk.
    private func nearest(_ wanted: (IslandMap.Prop) -> Bool) -> (x: Int, y: Int)? {
        let spot = scene.heroSpot
        return IslandMap.props(around: spot.x, spot.y, reach: 700)
            .filter { wanted($0) && spent[$0.id] == nil && engine.state.discovered.contains($0.region)
                && $0.region.yields.base(for: $0.kind.item) > 0 }
            .min { hypot(Double($0.x - spot.x), Double($0.y - spot.y)) < hypot(Double($1.x - spot.x), Double($1.y - spot.y)) }
            .map { ($0.x, $0.y) }
    }

    /// What a sensible castaway would be thinking about right now, and where to go for it.
    /// Body first, then the next step toward rescue.
    private func nudge() -> (icons: [CGImage], spot: (x: Int, y: Int)?)? {
        let state = engine.state
        let spot = scene.heroSpot
        func source(_ item: Item) -> (x: Int, y: Int)? { nearest { $0.kind.item == item } }

        if state.hoursLeft <= 2 { return ([Art.moon], IslandMap.bed) }
        if state.water == 0 || (state.needs.thirst < 50 && state.water < 2) {
            return state.discovered.contains(.stream)
                ? ([Art.murkyDrop], IslandMap.riverbank(y: spot.y))
                : ([Art.coconut, Art.drop], source(.cleanWater))
        }
        if state.count(.food) == 0 || (state.needs.hunger < 50 && state.count(.food) < 2) {
            return ([Art.fruit], source(.food))
        }
        if state.needs.temperature > 70 {
            // Out of the sun: the nearest thing that throws a shadow.
            return ([Art.thermometer, Art.sun, Art.treeIcon], nearestShade())
        }
        if state.needs.temperature < 25, !state.fireLitToday {
            return state.count(.wood) + state.count(.dryWood) > 0
                ? ([Art.thermometer, Art.flame], IslandMap.fire) : ([Art.thermometer, Art.log], source(.wood))
        }
        if !state.fireLitToday, state.hoursLeft <= 5 {
            return state.count(.wood) + state.count(.dryWood) > 0 ? ([Art.flame], IslandMap.fire) : ([Art.log, Art.flame], source(.wood))
        }

        // The way off the island, one step at a time.
        enum Step { case find(Region), make(Recipe) }
        let steps: [Step] = [
            .make(.map), .find(.palmGrove), .find(.stream), .make(.stoneAxe), .make(.dryingRack), .find(.jungle), .make(.rope),
            .make(.clayPot), .find(.ridge), .make(.torch), .find(.summit), .make(.signalFrame),
        ]
        for step in steps {
            switch step {
            case let .find(region):
                guard !state.discovered.contains(region) else { continue }
                return ([Art.compass, Art.icon(region)], IslandMap.gate(into: region, from: state.discovered, near: spot))
            case let .make(recipe):
                guard case let .structure(structure) = recipe.spec.output, !state.has(structure) else { continue }
                let spec = recipe.spec
                if let (item, _) = spec.cost.first(where: { state.count($0.0) < $0.1 }) {
                    return ([Art.picture(structure), Art.icon(item)], item == .dryWood ? nil : source(item))
                }
                if engine.level(.crafting) < spec.requiredLevel { return ([Art.picture(structure), Art.hammer, Art.up], nil) }
                if let region = spec.requiresRegion, region != here { return ([Art.picture(structure)], IslandMap.anchor(region)) }
                return ([Art.key("C"), Art.picture(structure)], nil)
            }
        }
        if state.count(.dryWood) < engine.balance.signalDryWood {
            return state.count(.wood) >= 3 ? ([Art.key("C"), Art.dryLog], nil) : ([Art.dryLog, Art.log], source(.wood))
        }
        return ([Art.ship, Art.flame], IslandMap.signal)
    }

    // MARK: Time

    private func tick(_ delta: TimeInterval) {
        guard NSApp.isActive else {
            held.removeAll()
            return
        }
        guard !paused, !crafting, !mapOpen, !intro else {
            scene.move(dx: 0, dy: 0, seconds: delta, canWalk: canWalk)
            return
        }
        switch phase {
        case .idle:
            if engine.state.hoursLeft == 0 {
                startNight()
                return
            }
            let dx: CGFloat = (held.isDisjoint(with: Key.right) ? 0 : 1) - (held.isDisjoint(with: Key.left) ? 0 : 1)
            let dy: CGFloat = (held.isDisjoint(with: Key.up) ? 0 : 1) - (held.isDisjoint(with: Key.down) ? 0 : 1)
            scene.move(dx: dx, dy: dy, seconds: delta, canWalk: canWalk)
            look()
            // Standing around wondering what to do: the castaway thinks of what matters most.
            let before = still
            still = dx == 0 && dy == 0 ? still + delta : 0
            if before < 2.5, still >= 2.5, let nudge = nudge() { scene.think(nudge.icons, toward: nudge.spot) }

            idle += delta / secondsPerHour
            if idle >= 1 {
                idle = 0
                let before = engine.state
                engine.perform(.rest(shaded: inShade()))
                scene.popup(sips(since: before))
                refresh()
                if engine.state.isOver { finish() }
            }
            clock = dayEnd - Double(engine.state.hoursLeft) + idle

        case let .working(action, from, elapsed, duration):
            let progress = min(1, (elapsed + delta) / duration)
            clock = from + Double(engine.hours(for: action)) * progress
            scene.setProgress(progress)
            if progress >= 1 {
                complete(action)
            } else {
                phase = .working(action, from: from, elapsed: elapsed + delta, duration: duration)
            }

        case let .dusk(from, elapsed):
            let progress = min(1, (elapsed + delta) / nightSeconds)
            clock = from + (24 - from) * progress
            if progress > 0.3 { scene.setAsleep(true) }
            if progress >= 1 {
                midnight()
            } else {
                phase = .dusk(from: from, elapsed: elapsed + delta)
            }

        case let .dawn(to, elapsed):
            let progress = min(1, (elapsed + delta) / nightSeconds)
            clock = to * progress
            if progress >= 1 {
                wake()
            } else {
                phase = .dawn(to: to, elapsed: elapsed + delta)
            }

        case .over:
            break
        }
        showClock()
    }

    private func showClock() {
        scene.setSky(hour: clock, raining: engine.state.weather == .rain)
        let night = clock >= 18.5 || clock < 5.5
        if night != isNight { isNight = night }
    }

    private func complete(_ action: Action) {
        let before = engine
        let result = engine.perform(action)
        working = nil
        scene.setProgress(nil)
        if let inHand, result.success {
            spent[inHand] = engine.state.day
            scene.collect(inHand)
        }
        inHand = nil

        var notes: [[CGImage]] = []
        for item in Item.allCases {
            let gained = engine.state.count(item) - before.state.count(item)
            if gained > 0 { notes.append([Art.icon(item), PixelFont.image("+\(gained)")]) }
        }
        for region in Region.allCases where engine.state.discovered.contains(region) && !before.state.discovered.contains(region) {
            notes.append([Art.compass, Art.icon(region), Art.check])
        }
        for structure in Structure.allCases where engine.state.has(structure) && !before.state.has(structure) {
            notes.append([Art.picture(structure), Art.check])
        }
        if engine.state.fireLitToday, !before.state.fireLitToday { notes.append([Art.flame, Art.check]) }
        if !result.success { notes.append([action.icon, Art.cross]) }
        notes += sips(since: before.state)
        for skill in Skill.allCases where engine.level(skill) > before.level(skill) {
            notes.append([Art.icon(skill), Art.up, Art.number(engine.level(skill))])
        }
        scene.popup(notes)
        let state = engine.state
        Sound.shared.play(
            !result.success ? .fail
                : state.discovered.count > before.state.discovered.count ? .discover
                : Skill.allCases.contains { engine.level($0) > before.level($0) } ? .levelUp
                : state.structures.count > before.state.structures.count ? .built : .gain)

        phase = .idle
        refresh()
        if engine.state.isOver { finish() }
    }

    private func startNight() {
        sleeping = true
        Sound.shared.play(.night)
        crafting = false
        idle = 0
        prompt = nil
        scene.setPrompt(nil)
        scene.move(dx: 0, dy: 0, seconds: 0, canWalk: canWalk)
        phase = .dusk(from: clock, elapsed: 0)
    }

    private func midnight() {
        engine.perform(.sleep)
        refresh()
        if engine.state.isOver {
            scene.setAsleep(false)
            sleeping = false
            finish()
        } else {
            phase = .dawn(to: dayEnd - Double(engine.state.hoursLeft), elapsed: 0)
        }
    }

    private func wake() {
        scene.setAsleep(false)
        sleeping = false
        phase = .idle
        // What was gathered a few days ago has come back.
        spent = spent.filter { engine.state.day - $0.value < regrowDays }
        scene.setSpent(Set(spent.keys))
        var notes = [[Art.sun, Art.number(engine.state.day)]]
        // A cold night shows in the morning.
        if engine.state.needs.temperature < engine.balance.shiverThreshold { notes.append([Art.thermometer, Art.cross]) }
        // Rain in the night: you drank, and a pot kept some.
        if engine.state.weather == .rain { notes.append([Art.rain, Art.drop] + (engine.state.has(.clayPot) ? [PixelFont.image("+3")] : [])) }
        scene.popup(notes)
        Sound.shared.play(.morning)
        refresh()
    }

    private func finish() {
        phase = .over
        prompt = nil
        scene.setPrompt(nil)
        guard let outcome = engine.state.outcome else { return }
        journal.record(engine.state)
        do {
            try journal.save(to: journalURL)
        } catch {
            saveError = error.localizedDescription
        }
        scene.finish(outcome)
        if case .rescued = outcome { Sound.shared.play(.rescued) } else { Sound.shared.play(.lost) }
        showClock()
    }

    private func refresh() {
        scene.sync(state: engine.state)
        showClock()
    }
}

// MARK: - How actions read on screen

extension Action {
    var icon: CGImage {
        switch self {
        case .gather(.cleanWater, _): Art.coconut
        case let .gather(item, _): Art.icon(item)
        case .fish: Art.fish
        case .fetchWater: Art.murkyDrop
        case .explore: Art.compass
        case .craft: Art.hammer
        case .makeFire: Art.flame
        case .lightSignal: Art.ship
        case .rest, .sleep: Art.moon
        }
    }
}
