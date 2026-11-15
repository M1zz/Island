import Foundation

public struct ActionResult: Sendable {
    public let success: Bool
    public let messages: [String]
}

/// Pure simulation. No rendering, no I/O — drive it from SpriteKit, a CLI, tests or bots.
public struct GameEngine: Sendable {
    public private(set) var state: GameState
    public let balance: Balance
    public let journal: Journal
    private var rng: SplitMix64

    public init(seed: UInt64, balance: Balance = .standard, journal: Journal = Journal()) {
        self.balance = balance
        self.journal = journal
        rng = SplitMix64(seed: seed)
        state = GameState(hoursPerDay: balance.hoursPerDay)
        startDay()
        state.log.append("Day 1. The pod is down and you are alive. Weather: \(state.weather.rawValue).")
    }

    public func level(_ skill: Skill) -> Int {
        state.skills.level(skill, balance: balance)
    }

    // MARK: - Costs & availability

    public func hours(for action: Action) -> Int {
        switch action {
        case let .gather(_, region): 2 + region.travelHours
        case .cutIce: 1 + Region.glacier.travelHours
        case let .explore(region): 3 + region.travelHours
        case let .craft(recipe): recipe.spec.hours + (recipe.spec.requiresRegion?.travelHours ?? 0)
        case .lightBurner: 1
        case .rest: 1
        case .sleep: 0
        }
    }

    public func canPerform(_ action: Action) -> Bool {
        guard !state.isOver else { return false }
        if case .sleep = action { return true }
        guard hours(for: action) <= state.hoursLeft else { return false }

        switch action {
        case let .gather(item, region):
            return state.discovered.contains(region) && region.yields.base(for: item) > 0
        case .cutIce:
            return state.discovered.contains(.glacier)
        case let .explore(region):
            return !state.discovered.contains(region)
                && state.discovered.contains(where: { $0.neighbors.contains(region) })
                && level(.exploration) >= region.requiredLevel
                && region.requiredTool.map(state.has) != false
        case let .craft(recipe):
            let spec = recipe.spec
            if case let .structure(structure) = spec.output, state.has(structure) { return false }
            if let required = spec.requiresStructure, !state.has(required) { return false }
            if let region = spec.requiresRegion, !state.discovered.contains(region) { return false }
            guard level(.crafting) >= spec.requiredLevel else { return false }
            return spec.cost.allSatisfy { state.count($0.0) >= $0.1 }
        case .lightBurner:
            return !state.burnerLit && state.count(.biomass) > 0
        case .rest, .sleep:
            return true
        }
    }

    /// Deterministically ordered list of everything the player can do right now.
    public var availableActions: [Action] {
        Self.allActions.filter(canPerform)
    }

    public static let allActions: [Action] = {
        var list: [Action] = []
        for region in Region.allCases {
            for item in [Item.air, .food, .biomass, .fiber, .ore] where region.yields.base(for: item) > 0 {
                list.append(.gather(item, region))
            }
        }
        list.append(.cutIce)
        for region in Region.allCases where region != .landing {
            list.append(.explore(region))
        }
        for recipe in Recipe.allCases {
            list.append(.craft(recipe))
        }
        list.append(.lightBurner)
        list.append(.sleep)
        return list
    }()

    /// The three machines, in order, for UI hints.
    public var terraformChecklist: [(structure: Structure, done: Bool)] {
        Structure.terraformers.map { ($0, state.has($0)) }
    }

    /// How much the planet turns each day with what stands now.
    public var terraformPerDay: Double {
        state.structures.reduce(0) { $0 + $1.terraformPerDay }
    }

    /// How far along the planet is, 0...1.
    private var turned: Double { min(1, state.terraform / 100) }

    // MARK: - Actions

    @discardableResult
    public mutating func perform(_ action: Action) -> ActionResult {
        guard canPerform(action) else {
            return ActionResult(success: false, messages: ["You can't do that right now."])
        }
        if case .sleep = action {
            let messages = endDay()
            state.log.append(contentsOf: messages)
            return ActionResult(success: true, messages: messages)
        }

        if case let .rest(shaded) = action {
            state.hoursLeft -= 1
            state.needs.fatigue = min(100, state.needs.fatigue + balance.awakeFatiguePerHour)
            var (messages, struck) = pass(hours: 1, open: !shaded, working: false)
            if state.needs.health <= 0 {
                state.outcome = .died(day: state.day, cause: struck ? .heatstroke : .injuries)
                messages.append("You did not get up again.")
            }
            state.log.append(contentsOf: messages)
            return ActionResult(success: true, messages: messages)
        }

        let cost = hours(for: action)
        state.hoursLeft -= cost
        let fatiguePerHour: Double
        if case .explore = action {
            fatiguePerHour = balance.exploreFatiguePerHour
        } else {
            fatiguePerHour = balance.fatiguePerHour
        }
        state.needs.fatigue = min(100, state.needs.fatigue + fatiguePerHour * Double(cost))

        var messages: [String] = []
        var success = true

        switch action {
        case let .gather(item, region):
            // Things grow as the planet turns.
            let growth = item == .food || item == .biomass ? 1 + balance.terraformGrowth * turned : 1
            let amount = rollYield(base: region.yields.base(for: item) * growth, skill: .foraging)
            state.inventory[item, default: 0] += amount
            success = amount > 0
            if item == .air, rng.chance(balance.podFallChance * max(0.25, 1 - 0.15 * Double(level(.foraging)))) {
                state.needs.health -= balance.injuryDamage
                messages.append("You slipped coming down from the pods.")
            }
            messages.append(item == .air
                ? "Tapped breath pods: +\(amount) air."
                : "Gathered \(amount) \(item.displayName.lowercased()) at the \(region.displayName.lowercased()).")
            messages += gainXP(10, .foraging, difficulty: region.difficulty, failed: !success,
                               key: "gather.\(item.rawValue).\(region.rawValue)")

        case .cutIce:
            let amount = 3 + level(.survival) / 3
            state.inventory[.ice, default: 0] += amount
            messages.append("Cut \(amount) ice from the glacier.")
            messages += gainXP(4, .survival, difficulty: 0, failed: false, key: "cutIce")

        case let .explore(region):
            let lvl = level(.exploration)
            let bonus = journal.knownRegions.contains(region) ? balance.journalExploreBonus : 0
            success = rng.chance(clamp(0.4 + 0.15 * Double(lvl - region.difficulty) + bonus, 0.05, 0.95))
            let rainRisk = state.weather == .storm ? 0.05 : 0
            let injuryChance = clamp(0.12 + 0.06 * Double(region.difficulty - lvl) + rainRisk, 0.02, 0.5)
            if rng.chance(injuryChance) {
                state.needs.health -= balance.injuryDamage
                messages.append("You got hurt while exploring.")
            }
            if success {
                state.discovered.insert(region)
                messages.append("Discovered the \(region.displayName.lowercased())!")
            } else {
                messages.append("You couldn't find a way to the \(region.displayName.lowercased()).")
            }
            messages += gainXP(25, .exploration, difficulty: region.difficulty, failed: !success,
                               key: "explore.\(region.rawValue)")

        case let .craft(recipe):
            let spec = recipe.spec
            let lvl = level(.crafting)
            success = rng.chance(clamp(0.65 + 0.12 * Double(lvl - spec.requiredLevel), 0.1, 0.98))
            if success {
                for (item, amount) in spec.cost {
                    state.inventory[item, default: 0] -= amount
                }
                switch spec.output {
                case let .structure(structure):
                    state.structures.insert(structure)
                case let .items(item, amount):
                    state.inventory[item, default: 0] += amount
                }
                messages.append("Built: \(recipe.displayName).")
            } else {
                messages.append("Building \(recipe.displayName.lowercased()) failed. Materials kept.")
            }
            messages += gainXP(spec.baseXP, .crafting, difficulty: spec.requiredLevel, failed: !success,
                               key: "craft.\(recipe.rawValue)")

        case .lightBurner:
            let lvl = level(.survival)
            state.inventory[.biomass, default: 0] -= 1
            var probability = 0.3 + 0.12 * Double(lvl)
            let storming = state.weather == .storm
            if storming {
                probability -= state.has(.dome) ? 0.1 : 0.25
            }
            success = rng.chance(clamp(probability, 0.05, 0.95))
            state.burnerLit = success
            if success, state.needs.temperature < 50 {
                state.needs.temperature = min(50, state.needs.temperature + balance.fireWarmth)
            }
            messages.append(success ? "The burner caught. Tonight is warm." : "The burner choked and went out.")
            messages += electrolyze()
            messages += gainXP(15, .survival, difficulty: 1 + (storming ? 1 : 0), failed: !success, key: "lightBurner")

        case .rest, .sleep:
            break
        }

        // An hour among the ice takes the heat off.
        if action == .cutIce, state.needs.temperature > 50 {
            state.needs.temperature = max(50, state.needs.temperature - balance.waterCool)
        }
        let (passing, struck) = pass(hours: cost, open: isUnderOpenSky(action), working: true)
        messages += passing

        if state.outcome == nil, state.needs.health <= 0 {
            state.outcome = .died(day: state.day, cause: struck ? .heatstroke : .injuries)
            messages.append(struck ? "The suit could not shed the heat." : "Your injuries were too much.")
        }
        state.log.append(contentsOf: messages)
        return ActionResult(success: success, messages: messages)
    }

    // MARK: - Internals

    /// Waking hours go by: the tank runs down and you get hungrier the whole time, not just overnight,
    /// and you open a canister when you need one if there is one.
    private mutating func pass(hours: Int, open: Bool, working: Bool) -> (messages: [String], heatstroke: Bool) {
        state.hoursSpentToday += hours
        wear(hours: hours)
        let struck = weather(hours: hours, open: open, working: working)
        return ((struck ? ["Heatstroke. You should not have stayed out in the sun."] : []) + breathe(), struck)
    }

    /// Whether doing this keeps you out under the sun. The pod is on open ground, so a dome is its only shade.
    private func isUnderOpenSky(_ action: Action) -> Bool {
        switch action {
        case let .gather(_, region), let .explore(region): region.isOpenSky
        case .cutIce: false
        case let .craft(recipe): recipe.spec.requiresRegion.map(\.isOpenSky) ?? !state.has(.dome)
        case .lightBurner: !state.has(.dome)
        case let .rest(shaded): !shaded
        case .sleep: false
        }
    }

    private mutating func wear(hours: Int) {
        let share = Double(hours) / Double(balance.hoursPerDay)
        // The more the planet has turned, the less the suit has to make up.
        let relief = 1 - balance.terraformAirRelief * turned
        state.needs.oxygen = max(0, state.needs.oxygen - balance.oxygenDecayPerDay * share * relief)
        state.needs.hunger = max(0, state.needs.hunger - balance.hungerDecayPerDay * share)
    }

    /// Body temperature, hour by hour: a storm chills, the midday sun under open sky heats,
    /// shade cools, and a dry hour warms you back up if you were cold. Returns whether you collapsed from the heat.
    private mutating func weather(hours: Int, open: Bool, working: Bool) -> Bool {
        // `hoursLeft` has already been charged for these hours.
        let start = balance.dawnHour + balance.hoursPerDay - state.hoursLeft - hours
        for hour in start..<start + hours {
            var heat = state.needs.temperature
            if state.weather == .storm {
                heat -= balance.stormChillPerHour
            } else if heat < 50 {
                heat = min(50, heat + balance.sunWarmthPerHour)
            } else if !open {
                heat = max(50, heat - balance.shadeCoolPerHour)
            } else if hour >= balance.middayStart && hour < balance.middayEnd {
                heat += working ? balance.sunHeatWorking : balance.sunHeatResting
            }
            state.needs.temperature = clamp(heat, 0, 100)
            if heat > balance.sweatThreshold {
                state.needs.oxygen = max(0, state.needs.oxygen - balance.heatAirPerHour)
            }
        }
        guard state.needs.temperature >= 100 else { return false }
        state.needs.health -= balance.heatstrokeDamage
        state.needs.fatigue = min(100, state.needs.fatigue + balance.heatstrokeFatigue)
        // You come to in whatever shade you crawled into.
        state.needs.temperature = 80
        return true
    }

    /// The daylight left when you turn in is spent at camp: out of the sun, or drying off, or under a roof.
    private mutating func settle(hours: Int) {
        let roof = state.has(.dome)
        for _ in 0..<hours {
            var heat = state.needs.temperature
            if state.weather == .storm {
                if !roof { heat -= balance.stormChillPerHour }
            } else if heat < 50 {
                heat = min(50, heat + balance.sunWarmthPerHour)
            } else {
                heat = max(50, heat - balance.shadeCoolPerHour)
            }
            state.needs.temperature = clamp(heat, 0, 100)
        }
    }

    /// With the burner running and an electrolyzer to feed, ice is split into air you can breathe.
    private mutating func electrolyze() -> [String] {
        guard state.burnerLit, state.has(.electrolyzer), state.count(.ice) > 0 else { return [] }
        let amount = state.count(.ice)
        state.inventory[.air, default: 0] += amount
        state.inventory[.ice] = 0
        return ["Split \(amount) ice into air."]
    }

    /// Open canisters while the tank is low and there are any.
    private mutating func breathe() -> [String] {
        while state.needs.oxygen <= balance.breatheThreshold && state.count(.air) > 0 {
            state.inventory[.air, default: 0] -= 1
            state.needs.oxygen = min(100, state.needs.oxygen + balance.breathRestore)
        }
        return []
    }

    private mutating func rollYield(base: Double, skill: Skill) -> Int {
        let multiplier = 1 + balance.yieldPerLevel * Double(level(skill))
        let variance = 0.7 + 0.6 * rng.unit()
        return Int((base * multiplier * variance + 0.5).rounded(.down))
    }

    private mutating func gainXP(_ base: Double, _ skill: Skill, difficulty: Int, failed: Bool, key: String) -> [String] {
        let before = level(skill)
        let novelty = state.firstTimes.insert(key).inserted ? balance.noveltyMultiplier : 1
        let difficultyMultiplier = clamp(1 + balance.difficultyStep * Double(difficulty - before), 0.5, 2.0)
        let failMultiplier = failed ? balance.failMultiplier : 1
        let repeats = state.actionsToday[key, default: 0]
        let repeatMultiplier = pow(balance.repeatPenaltyBase, Double(repeats))
        state.actionsToday[key] = repeats + 1

        state.skills.add(base * novelty * difficultyMultiplier * failMultiplier * repeatMultiplier, to: skill)
        let after = level(skill)
        return after > before ? ["\(skill.displayName) improved to level \(after)!"] : []
    }

    private mutating func endDay() -> [String] {
        var messages: [String] = []
        let hasShelter = state.has(.dome)

        // Sleep
        var fatigue = state.needs.fatigue - balance.restRecoveryPerHour * Double(state.hoursLeft)
        fatigue -= hasShelter ? balance.shelterSleepRecovery : balance.sleepRecovery
        if state.weather == .storm && !hasShelter {
            fatigue += balance.stormSleepPenalty
            messages.append("The storm kept you up all night.")
        }
        settle(hours: max(0, balance.hoursPerDay - state.hoursSpentToday))
        // The night cools you off, then takes heat. The burner and a dome keep some of it in,
        // and the nights grow milder as the planet turns.
        var chill = balance.nightChill - balance.terraformNightWarmth * turned
        if state.burnerLit { chill -= balance.fireNightWarmth }
        if hasShelter { chill -= balance.shelterNightWarmth }
        if state.weather == .storm && !hasShelter { chill += balance.stormNightChill }
        state.needs.temperature = max(0, min(50, state.needs.temperature) - max(0, chill))
        if state.needs.temperature < balance.shiverThreshold {
            fatigue += balance.shiverFatigue
            messages.append("You shivered through the night.")
        }
        state.needs.fatigue = clamp(fatigue, 0, 100)

        // The rest of the day's air and hunger, for the hours slept through.
        wear(hours: max(0, balance.hoursPerDay - state.hoursSpentToday))
        messages += electrolyze()
        messages += breathe()

        // Eat
        let meal = state.burnerLit ? balance.cookedMealRestore : balance.mealRestore
        while state.needs.hunger <= balance.eatThreshold && state.count(.food) > 0 {
            state.inventory[.food, default: 0] -= 1
            state.needs.hunger = min(100, state.needs.hunger + meal)
        }
        if state.count(.food) > balance.foodSpoilThreshold {
            state.inventory[.food, default: 0] -= 1
            messages.append("Some food spoiled.")
        }

        // Damage & recovery
        if state.needs.oxygen <= 0 {
            state.needs.health -= balance.suffocationDamage
            messages.append("The tank is empty.")
        }
        if state.needs.hunger <= 0 {
            state.needs.health -= balance.starvationDamage
            messages.append("You are starving.")
        }
        if state.needs.temperature <= 0 {
            state.needs.health -= balance.hypothermiaDamage
            messages.append("The cold is in your bones.")
        }
        if state.needs.oxygen > 50 && state.needs.hunger > 50 && state.needs.temperature > 25 && state.needs.temperature < 75 && state.needs.fatigue < 50 {
            state.needs.health = min(100, state.needs.health + balance.dailyRegen)
        }

        if state.needs.health <= 0 {
            let cause: DeathCause = state.needs.oxygen <= 0 ? .suffocation
                : state.needs.hunger <= 0 ? .starvation : state.needs.temperature <= 0 ? .exposure : .injuries
            state.outcome = .died(day: state.day, cause: cause)
            messages.append("You did not survive the night (\(cause.rawValue)).")
            return messages
        }

        // The machines ran all night.
        if terraformPerDay > 0 {
            state.terraform = min(100, state.terraform + terraformPerDay)
            messages.append("The planet has turned \(Int(state.terraform))%.")
        }
        if state.terraform >= 100 {
            state.outcome = .habitable(day: state.day)
            messages.append("You take the helmet off. The air holds.")
            return messages
        }

        state.day += 1
        if state.day >= balance.winterDay {
            state.outcome = .winter
            messages.append("The long winter arrives. The planet was not ready.")
            return messages
        }

        startDay()
        messages.append("Day \(state.day) begins. Weather: \(state.weather.rawValue). Hours: \(state.hoursLeft).")
        return messages
    }

    private mutating func startDay() {
        state.weather = rng.chance(balance.stormChance) ? .storm : .clear
        state.burnerLit = false
        state.hoursSpentToday = 0
        state.actionsToday = [:]
        let lostHours = Int(state.needs.fatigue / balance.fatiguePerLostHour)
        state.hoursLeft = max(2, balance.hoursPerDay - lostHours)
    }
}
