import AppKit
import IslandCore

/// What Space would do where the castaway stands.
struct Prompt: Equatable {
    let action: Action
    let hours: Int
    /// What is in the way, if Space would do nothing.
    let blocker: Blocker?

    enum Blocker: Equatable {
        case level(Int), noPath, rescueList, wood, daylight
    }

    var enabled: Bool { blocker == nil }

    /// The prompt as pictures: the key and what it does, or the thing and what it still needs.
    var icons: [CGImage] {
        switch blocker {
        case nil: [Art.spaceKey, action.icon] + (hours > 0 ? [Art.hourglass, Art.number(hours)] : [])
        case let .level(level): [action.icon, Art.cross, Art.icon(Skill.exploration), Art.up, Art.number(level)]
        case .noPath: [action.icon, Art.cross]
        case .rescueList: [action.icon, Art.cross, Art.todo]
        case .wood: [action.icon, Art.cross, Art.log]
        case .daylight: [action.icon, Art.cross, Art.hourglass]
        }
    }
}

/// Runs `GameEngine` in real time: you walk the island yourself, hours pass on their own,
/// work takes a while, night follows day. The rules stay in the engine. An idle hour is the
/// engine's `.rest`, so wandering costs exactly what sleeping early would.
final class Game: ObservableObject {
    @Published private(set) var engine: GameEngine
    @Published private(set) var journal: Journal
    @Published private(set) var here: Region = .beach
    @Published private(set) var prompt: Prompt?
    @Published private(set) var working: Action?
    @Published private(set) var sleeping = false
    @Published private(set) var isNight = false
    @Published private(set) var saveError: String?
    @Published var crafting = false
    @Published var paused = false

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
        static let digits: [UInt16] = [18, 19, 20, 21, 23]
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
    private var nearProp: Int?
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
        refresh()
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
            } else if !crafting, let prompt, prompt.enabled {
                begin(prompt.action)
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
    }

    func toggleMap() {
        guard !engine.state.isOver else { return }
        crafting = false
        mapOpen.toggle()
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
        if case .gather = action, let nearProp { scene.shake(prop: nearProp) }
        working = action
        scene.setPrompt(nil)
        phase = .working(action, from: clock, elapsed: 0, duration: 0.9 + Double(engine.hours(for: action)) * 0.8)
    }

    func restart() {
        saveError = nil
        engine = GameEngine(seed: .random(in: 1...UInt64.max), journal: journal)
        phase = .idle
        idle = 0
        working = nil
        sleeping = false
        crafting = false
        mapOpen = false
        scene.reset()
        refresh()
    }

    // MARK: Looking around

    private func canWalk(_ x: Int, _ y: Int) -> Bool {
        guard let region = IslandMap.region(x: x, y: y) else { return false }
        return IslandMap.shore(x, y) < 0.996 && engine.state.discovered.contains(region) && !IslandMap.blocked(x, y)
    }

    /// The closest thing worth doing from where the castaway stands.
    private func look() {
        let spot = scene.heroSpot
        let state = engine.state
        func distance(_ x: Int, _ y: Int) -> Double { hypot(Double(spot.x - x), Double(spot.y - y)) }
        if let region = IslandMap.region(x: spot.x, y: spot.y), region != here { here = region }

        var found: Action?
        nearProp = nil
        if distance(IslandMap.bed.x, IslandMap.bed.y) < 12 {
            found = .sleep
        } else if distance(IslandMap.fire.x, IslandMap.fire.y) < 13, !state.fireLitToday {
            found = .makeFire
        } else if distance(IslandMap.signal.x, IslandMap.signal.y) < 14 {
            found = .lightSignal
        } else {
            var best = 13.0
            for (index, prop) in IslandMap.props.enumerated() {
                let item = prop.prop.item
                guard prop.region.yields.base(for: item) > 0,
                      state.discovered.contains(prop.region) else { continue }
                // A giant's trunk keeps you at arm's length.
                let d = distance(prop.x, prop.y - 2) - (prop.prop.isTall ? 8 : 0)
                if d < best {
                    best = d
                    nearProp = index
                    found = .gather(item, prop.region)
                }
            }
        }
        if found == nil, state.discovered.contains(.stream), IslandMap.streamDistance(spot.x, spot.y) < 22 {
            found = .fetchWater
        }
        if found == nil {
            // Fog within reach means land to explore.
            for step in 0..<16 {
                let angle = Double(step) / 16 * 2 * .pi
                let x = spot.x + Int((cos(angle) * 10).rounded()), y = spot.y + Int((sin(angle) * 10).rounded())
                if let region = IslandMap.region(x: x, y: y), !state.discovered.contains(region) {
                    found = .explore(region)
                    break
                }
            }
        }
        if found == nil, here == .beach, IslandMap.shore(spot.x, spot.y) > 0.982 {
            found = .fish
        }

        let next = found.map { action in
            Prompt(action: action, hours: action == .sleep ? 0 : engine.hours(for: action),
                   blocker: engine.canPerform(action) ? nil : blocker(action))
        }
        if next != prompt { prompt = next }
        scene.setPrompt(next)
    }

    /// Why an action is locked right now.
    private func blocker(_ action: Action) -> Prompt.Blocker {
        let state = engine.state
        switch action {
        case let .explore(region):
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

    // MARK: Time

    private func tick(_ delta: TimeInterval) {
        guard NSApp.isActive else {
            held.removeAll()
            return
        }
        guard !paused, !crafting, !mapOpen else {
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

            idle += delta / secondsPerHour
            if idle >= 1 {
                idle = 0
                engine.perform(.rest)
                refresh()
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
        for skill in Skill.allCases where engine.level(skill) > before.level(skill) {
            notes.append([Art.icon(skill), Art.up, Art.number(engine.level(skill))])
        }
        scene.popup(notes)

        phase = .idle
        refresh()
        if engine.state.isOver { finish() }
    }

    private func startNight() {
        sleeping = true
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
        scene.popup([[Art.sun, Art.number(engine.state.day)]])
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
        case let .gather(item, _): Art.icon(item)
        case .fish: Art.fish
        case .fetchWater: Art.drop
        case .explore: Art.compass
        case .craft: Art.hammer
        case .makeFire: Art.flame
        case .lightSignal: Art.ship
        case .rest, .sleep: Art.moon
        }
    }
}
