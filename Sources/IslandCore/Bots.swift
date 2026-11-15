/// Automated players for balancing. Each bot represents a play style.
public protocol Bot {
    var name: String { get }
    mutating func choose(in engine: GameEngine, rng: inout SplitMix64) -> Action
}

/// A clueless first-timer: picks any available action at random.
public struct RandomBot: Bot {
    public let name = "random"
    public init() {}

    public mutating func choose(in engine: GameEngine, rng: inout SplitMix64) -> Action {
        let actions = engine.availableActions
        return actions[rng.index(actions.count)]
    }
}

/// A specialist: keeps itself fed and breathing but never builds anything.
/// Exists to prove that staying alive does not turn a planet.
public struct ForagerBot: Bot {
    public let name = "forager"
    public init() {}

    public mutating func choose(in engine: GameEngine, rng: inout SplitMix64) -> Action {
        let state = engine.state
        var plan: [Action] = [.explore(.grove)]
        if state.count(.air) < 3 { plan += [.gather(.air, .grove), .gather(.air, .landing)] }
        if state.count(.food) < 6 { plan += [.gather(.food, .grove), .gather(.food, .landing)] }
        plan.append(.sleep)
        return plan.first(where: engine.canPerform) ?? .sleep
    }
}

/// A competent player following a sensible priority list.
public struct PlannerBot: Bot {
    public let name = "planner"
    public init() {}

    /// Tools come just before the region they open; each terraformer as soon as it can go up.
    static let buildOrder: [Recipe] = [.cutter, .smelter, .electrolyzer, .warmer, .tether, .thawer, .lamp, .seeder, .dome]

    static func gatherSpots(for item: Item) -> [Region] {
        switch item {
        case .biomass: [.forest, .grove, .landing]
        case .fiber: [.grove, .forest, .glacier]
        case .ore: [.rim, .glacier]
        case .food: [.grove, .forest, .landing]
        case .ice, .air, .metal: []
        }
    }

    /// How to come by more of something: smelt it if it is metal, otherwise go and get it.
    static func ways(toGet item: Item) -> [Action] {
        (item == .metal ? [.craft(.metal)] + gatherSpots(for: .ore).map { Action.gather(.ore, $0) } : [])
            + gatherSpots(for: item).map { Action.gather(item, $0) }
    }

    public mutating func choose(in engine: GameEngine, rng: inout SplitMix64) -> Action {
        let state = engine.state
        var plan: [Action] = []
        let burnerTries = state.actionsToday["lightBurner", default: 0]

        // Too hot: to the ice if there is any, else out of the sun.
        if state.needs.temperature > 75 { plan += [.cutIce, .rest(shaded: true)] }

        // 1. Stay alive
        if state.has(.electrolyzer) {
            // Ice is air once the burner runs.
            if state.count(.air) + state.count(.ice) < 4 { plan.append(.cutIce) }
            if state.count(.ice) > 0, !state.burnerLit, burnerTries < 3 {
                plan += [.lightBurner] + Self.ways(toGet: .biomass)
            }
        }
        if state.count(.air) < 2 { plan += [.gather(.air, .grove), .gather(.air, .landing)] }
        if !state.discovered.contains(.grove) { plan.append(.explore(.grove)) }
        if state.count(.food) < 4 { plan += Self.ways(toGet: .food) }
        if !state.discovered.contains(.glacier) { plan.append(.explore(.glacier)) }

        // Cold: get the burner going.
        if state.needs.temperature < 25, !state.burnerLit, burnerTries < 2 { plan.append(.lightBurner) }

        // 2. Build whatever is buildable, then push toward the vent
        plan += Self.buildOrder.map { Action.craft($0) }
        plan += [.explore(.forest), .explore(.rim), .explore(.vent)]

        // 3. Gather materials for the next missing build
        if let next = Self.buildOrder.first(where: { recipe in
            if case let .structure(structure) = recipe.spec.output { return !state.has(structure) }
            return false
        }) {
            for (item, amount) in next.spec.cost where state.count(item) < amount {
                plan += Self.ways(toGet: item)
            }
        }

        // 4. Keep a food buffer
        if state.count(.food) < 6 { plan += Self.ways(toGet: .food) }

        plan.append(.sleep)
        return plan.first(where: engine.canPerform) ?? .sleep
    }
}

/// Plays one full run and returns the final state.
public func simulate<B: Bot>(seed: UInt64, bot: inout B, balance: Balance = .standard, journal: Journal = Journal()) -> GameState {
    var engine = GameEngine(seed: seed, balance: balance, journal: journal)
    var botRNG = SplitMix64(seed: seed ^ 0xA5A5_A5A5_A5A5_A5A5)
    var guardCounter = 0
    while !engine.state.isOver && guardCounter < 10_000 {
        let action = bot.choose(in: engine, rng: &botRNG)
        engine.perform(action)
        guardCounter += 1
    }
    return engine.state
}
