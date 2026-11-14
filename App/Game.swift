import AppKit
import IslandCore

/// What Space would do where the castaway stands.
struct Prompt: Equatable {
    let action: Action
    let enabled: Bool
    let text: String
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
    @Published private(set) var clockText = ""
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
            crafting = false
            mapOpen.toggle()
        case Key.craft:
            if case .idle = phase, !paused {
                mapOpen = false
                crafting.toggle()
            }
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
        scene.setPrompt(nil, enabled: true)
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
        return IslandMap.shore(x, y) < 0.996 && engine.state.discovered.contains(region)
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
                guard let item = prop.prop.item, prop.region.yields.base(for: item) > 0,
                      state.discovered.contains(prop.region) else { continue }
                let d = distance(prop.x, prop.y - 2)
                if d < best {
                    best = d
                    nearProp = index
                    found = .gather(item, prop.region)
                }
            }
        }
        if found == nil, state.discovered.contains(.stream), IslandMap.streamDistance(spot.x, spot.y) < 15 {
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
            let enabled = engine.canPerform(action)
            let hours = action == .sleep ? "" : " \(engine.hours(for: action))h"
            return Prompt(action: action, enabled: enabled,
                          text: enabled ? "Space: \(action.title)\(hours)" : why(action) ?? action.title)
        }
        if next != prompt { prompt = next }
        scene.setPrompt(next?.text, enabled: next?.enabled ?? true)
    }

    /// Why an action is locked right now.
    private func why(_ action: Action) -> String? {
        let state = engine.state
        switch action {
        case let .explore(region):
            if engine.level(.exploration) < region.requiredLevel { return "Needs Exploration Lv \(region.requiredLevel)" }
            if !state.discovered.contains(where: { $0.neighbors.contains(region) }) { return "No way through from here" }
        case .lightSignal:
            if !engine.canPerform(action) { return "Finish the rescue list first" }
        case .makeFire:
            if state.count(.wood) + state.count(.dryWood) == 0 { return "A fire needs wood" }
        default:
            break
        }
        return engine.hours(for: action) > state.hoursLeft ? "Not enough daylight" : nil
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
        let minutes = Int(clock * 6) * 10
        let text = String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
        if text != clockText { clockText = text }
        let night = clock >= 18.5 || clock < 5.5
        if night != isNight { isNight = night }
    }

    private func complete(_ action: Action) {
        let before = engine
        let result = engine.perform(action)
        working = nil
        scene.setProgress(nil)

        var notes: [String] = []
        for item in Item.allCases {
            let gained = engine.state.count(item) - before.state.count(item)
            if gained > 0 { notes.append("+\(gained) \(item.displayName.lowercased())") }
        }
        if engine.state.discovered.count > before.state.discovered.count { notes.append("Discovered!") }
        if engine.state.structures.count > before.state.structures.count { notes.append("Built!") }
        if engine.state.fireLitToday, !before.state.fireLitToday { notes.append("Fire lit!") }
        if !result.success { notes.append("No luck...") }
        for skill in Skill.allCases where engine.level(skill) > before.level(skill) {
            notes.append("\(skill.displayName) Lv \(engine.level(skill))!")
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
        scene.setPrompt(nil, enabled: true)
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
        scene.popup(["Day \(engine.state.day)"])
        refresh()
    }

    private func finish() {
        phase = .over
        prompt = nil
        scene.setPrompt(nil, enabled: true)
        guard let outcome = engine.state.outcome else { return }
        journal.record(engine.state)
        do {
            try journal.save(to: journalURL)
        } catch {
            saveError = "Could not save the journal."
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
    var title: String {
        switch self {
        case let .gather(item, _): "Gather \(item.displayName.lowercased())"
        case .fish: "Go fishing"
        case .fetchWater: "Fetch water"
        case .explore: "Explore"
        case let .craft(recipe): recipe.displayName
        case .makeFire: "Make a fire"
        case .lightSignal: "Light the signal"
        case .rest: "Rest"
        case .sleep: "Sleep till morning"
        }
    }

    var doing: String {
        switch self {
        case .gather: "Gathering..."
        case .fish: "Fishing..."
        case .fetchWater: "Fetching water..."
        case .explore: "Exploring..."
        case .craft: "Crafting..."
        case .makeFire: "Making a fire..."
        case .lightSignal: "Lighting the signal..."
        case .rest, .sleep: "Resting..."
        }
    }

    var icon: CGImage {
        switch self {
        case let .gather(item, _): Art.icon(item)
        case .fish: Art.fruit
        case .fetchWater: Art.drop
        case .explore: Art.compass
        case let .craft(recipe): recipe == .dryWood ? Art.dryLog : Art.log
        case .makeFire, .lightSignal: Art.flame
        case .rest, .sleep: Art.moon
        }
    }
}
