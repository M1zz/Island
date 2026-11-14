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

/// A specialist: keeps itself fed and watered but never invests in anything else.
/// Exists to prove that "being good at one thing" does not get you rescued.
public struct ForagerBot: Bot {
    public let name = "forager"
    public init() {}

    public mutating func choose(in engine: GameEngine, rng: inout SplitMix64) -> Action {
        let state = engine.state
        var plan: [Action] = []
        if state.count(.water) < 4 { plan.append(.fetchWater) }
        plan.append(.explore(.stream))
        plan.append(.explore(.palmGrove))
        if state.count(.food) < 6 {
            plan += [.gather(.food, .palmGrove), .fish, .gather(.food, .beach)]
        }
        plan.append(.sleep)
        return plan.first(where: engine.canPerform) ?? .sleep
    }
}

/// A competent player following a sensible priority list.
public struct PlannerBot: Bot {
    public let name = "planner"
    public init() {}

    static let buildOrder: [Recipe] = [.dryingRack, .clayPot, .shelter, .signalFrame]

    static func gatherSpots(for item: Item) -> [Region] {
        switch item {
        case .wood: [.jungle, .palmGrove, .beach]
        case .fiber: [.palmGrove, .jungle, .stream]
        case .stone: [.ridge, .stream]
        case .food: [.palmGrove, .jungle, .beach]
        case .water, .dryWood: []
        }
    }

    public mutating func choose(in engine: GameEngine, rng: inout SplitMix64) -> Action {
        let state = engine.state
        let balance = engine.balance
        var plan: [Action] = [.lightSignal]

        // 1. Stay alive
        if state.count(.water) < 4 { plan.append(.fetchWater) }
        if !state.discovered.contains(.stream) { plan.append(.explore(.stream)) }
        if state.count(.food) < 4 {
            plan += Self.gatherSpots(for: .food).map { Action.gather(.food, $0) } + [Action.fish]
        }
        if !state.discovered.contains(.palmGrove) { plan.append(.explore(.palmGrove)) }

        // 2. Build whatever is buildable, then push toward the summit
        plan += Self.buildOrder.map { Action.craft($0) }
        plan += [.explore(.jungle), .explore(.ridge), .explore(.summit)]

        // 3. Practice fire (max two tries a day, dry wood only)
        if !state.fireLitToday && state.actionsToday["makeFire", default: 0] < 2 && state.count(.dryWood) > 0 {
            plan.append(.makeFire)
        }

        // 4. Gather materials for the next missing structure
        if let next = Self.buildOrder.first(where: { recipe in
            if case let .structure(structure) = recipe.spec.output { return !state.has(structure) }
            return false
        }) {
            for (item, amount) in next.spec.cost where state.count(item) < amount {
                plan += Self.gatherSpots(for: item).map { Action.gather(item, $0) }
            }
        }

        // 5. Stockpile dry wood for the signal
        if state.count(.dryWood) < balance.signalDryWood + 3 {
            plan.append(.craft(.dryWood))
            plan += Self.gatherSpots(for: .wood).map { Action.gather(.wood, $0) }
        }

        // 6. Keep a food buffer
        if state.count(.food) < 6 {
            plan += Self.gatherSpots(for: .food).map { Action.gather(.food, $0) } + [Action.fish]
        }

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
