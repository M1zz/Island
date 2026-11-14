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
        state.log.append("Day 1. You wake up on an unknown beach. Weather: \(state.weather.rawValue).")
    }

    public func level(_ skill: Skill) -> Int {
        state.skills.level(skill, balance: balance)
    }

    // MARK: - Costs & availability

    public func hours(for action: Action) -> Int {
        switch action {
        case let .gather(_, region): 2 + region.travelHours
        case .fish: 3
        case .fetchWater: 1 + Region.stream.travelHours
        case let .explore(region): 3 + region.travelHours
        case let .craft(recipe): recipe.spec.hours + (recipe.spec.requiresRegion?.travelHours ?? 0)
        case .makeFire: 1
        case .lightSignal: 2 + Region.summit.travelHours
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
        case .fish:
            return true
        case .fetchWater:
            return state.discovered.contains(.stream)
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
        case .makeFire:
            return !state.fireLitToday && (state.count(.dryWood) > 0 || state.count(.wood) > 0)
        case .lightSignal:
            return state.discovered.contains(.summit)
                && state.has(.signalFrame)
                && state.count(.dryWood) >= balance.signalDryWood
                && level(.survival) >= balance.signalMinSurvival
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
            for item in [Item.cleanWater, .food, .wood, .fiber, .stone] where region.yields.base(for: item) > 0 {
                list.append(.gather(item, region))
            }
        }
        list.append(.fish)
        list.append(.fetchWater)
        for region in Region.allCases where region != .beach {
            list.append(.explore(region))
        }
        for recipe in Recipe.allCases {
            list.append(.craft(recipe))
        }
        list.append(.makeFire)
        list.append(.lightSignal)
        list.append(.sleep)
        return list
    }()

    /// Rescue checklist, for UI hints.
    public var rescueChecklist: [(label: String, done: Bool)] {
        [
            ("Find the summit", state.discovered.contains(.summit)),
            ("Build a signal frame", state.has(.signalFrame)),
            ("Stockpile \(balance.signalDryWood) dry wood (\(state.count(.dryWood)))",
             state.count(.dryWood) >= balance.signalDryWood),
            ("Survival level \(balance.signalMinSurvival)", level(.survival) >= balance.signalMinSurvival),
        ]
    }

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
            let amount = rollYield(base: region.yields.base(for: item), skill: .foraging)
            state.inventory[item, default: 0] += amount
            success = amount > 0
            if item == .cleanWater, rng.chance(balance.palmFallChance * max(0.25, 1 - 0.15 * Double(level(.foraging)))) {
                state.needs.health -= balance.injuryDamage
                messages.append("You slipped coming down the palm.")
            }
            messages.append(item == .cleanWater
                ? "Opened coconuts: +\(amount) clean water."
                : "Gathered \(amount) \(item.displayName.lowercased()) at the \(region.displayName.lowercased()).")
            messages += gainXP(10, .foraging, difficulty: region.difficulty, failed: !success,
                               key: "gather.\(item.rawValue).\(region.rawValue)")

        case .fish:
            let lvl = level(.foraging)
            success = rng.chance(clamp(0.35 + 0.08 * Double(lvl), 0.05, 0.95))
            if success {
                let amount = 3 + lvl / 2
                state.inventory[.food, default: 0] += amount
                messages.append("Caught fish: +\(amount) food.")
            } else {
                messages.append("Nothing bit today.")
            }
            messages += gainXP(12, .foraging, difficulty: 1, failed: !success, key: "fish")

        case .fetchWater:
            let amount = 3 + level(.survival) / 3
            state.inventory[.water, default: 0] += amount
            messages.append("Fetched \(amount) raw water from the stream.")
            messages += gainXP(4, .survival, difficulty: 0, failed: false, key: "fetchWater")

        case let .explore(region):
            let lvl = level(.exploration)
            let bonus = journal.knownRegions.contains(region) ? balance.journalExploreBonus : 0
            success = rng.chance(clamp(0.4 + 0.15 * Double(lvl - region.difficulty) + bonus, 0.05, 0.95))
            let rainRisk = state.weather == .rain ? 0.05 : 0
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
                messages.append("Crafted: \(recipe.displayName).")
            } else {
                messages.append("Crafting \(recipe.displayName.lowercased()) failed. Materials kept.")
            }
            messages += gainXP(spec.baseXP, .crafting, difficulty: spec.requiredLevel, failed: !success,
                               key: "craft.\(recipe.rawValue)")

        case .makeFire:
            let lvl = level(.survival)
            let usesDryWood = state.count(.dryWood) > 0
            state.inventory[usesDryWood ? Item.dryWood : Item.wood, default: 0] -= 1
            var probability = 0.3 + 0.12 * Double(lvl) - (usesDryWood ? 0 : 0.25)
            let raining = state.weather == .rain
            if raining {
                probability -= state.has(.shelter) ? 0.1 : 0.25
            }
            success = rng.chance(clamp(probability, 0.05, 0.95))
            state.fireLitToday = success
            if success, state.needs.temperature < 50 {
                state.needs.temperature = min(50, state.needs.temperature + balance.fireWarmth)
            }
            messages.append(success ? "The fire caught. Tonight you eat cooked food." : "The fire died out.")
            messages += boil()
            messages += gainXP(15, .survival, difficulty: 1 + (raining ? 1 : 0), failed: !success, key: "makeFire")

        case .lightSignal:
            let lvl = level(.survival)
            let rainPenalty = state.weather == .rain ? 0.3 : 0
            success = rng.chance(clamp(0.55 + 0.15 * Double(lvl - balance.signalMinSurvival) - rainPenalty, 0.05, 0.95))
            if success {
                state.outcome = .rescued(day: state.day)
                messages.append("The signal fire roars on the summit. A ship turns toward the island.")
            } else {
                state.inventory[.dryWood, default: 0] -= balance.signalFailureWoodLoss
                messages.append("The signal fire sputtered out. You lost \(balance.signalFailureWoodLoss) dry wood.")
            }
            messages += gainXP(40, .survival, difficulty: 3, failed: !success, key: "lightSignal")

        case .rest, .sleep:
            break
        }

        // Wading in for water or standing in the surf takes the heat off.
        if action == .fetchWater, state.needs.temperature > 50 {
            state.needs.temperature = max(50, state.needs.temperature - balance.waterCool)
        }
        let (passing, struck) = pass(hours: cost, open: isUnderOpenSky(action), working: true)
        messages += passing

        if state.outcome == nil, state.needs.health <= 0 {
            state.outcome = .died(day: state.day, cause: struck ? .heatstroke : .injuries)
            messages.append(struck ? "The sun was too much." : "Your injuries were too much.")
        }
        state.log.append(contentsOf: messages)
        return ActionResult(success: success, messages: messages)
    }

    // MARK: - Internals

    /// Waking hours go by: you get thirstier and hungrier the whole time, not just overnight,
    /// and you drink when you need to if there is anything to drink.
    private mutating func pass(hours: Int, open: Bool, working: Bool) -> (messages: [String], heatstroke: Bool) {
        state.hoursSpentToday += hours
        wear(hours: hours)
        let struck = weather(hours: hours, open: open, working: working)
        return ((struck ? ["Heatstroke. You should not have stayed out in the sun."] : []) + drink(), struck)
    }

    /// Whether doing this keeps you out under the sun. Camp is on the beach, so a shelter is its only shade.
    private func isUnderOpenSky(_ action: Action) -> Bool {
        switch action {
        case let .gather(_, region), let .explore(region): region.isOpenSky
        case .fish, .lightSignal: true
        case .fetchWater: false
        case let .craft(recipe): recipe.spec.requiresRegion.map(\.isOpenSky) ?? !state.has(.shelter)
        case .makeFire: !state.has(.shelter)
        case let .rest(shaded): !shaded
        case .sleep: false
        }
    }

    private mutating func wear(hours: Int) {
        let share = Double(hours) / Double(balance.hoursPerDay)
        state.needs.thirst = max(0, state.needs.thirst - balance.thirstDecayPerDay * share)
        state.needs.hunger = max(0, state.needs.hunger - balance.hungerDecayPerDay * share)
    }

    /// Body temperature, hour by hour: rain chills, the midday sun under open sky heats,
    /// shade cools, and a dry hour warms you back up if you were cold. Returns whether you collapsed from the heat.
    private mutating func weather(hours: Int, open: Bool, working: Bool) -> Bool {
        // `hoursLeft` has already been charged for these hours.
        let start = balance.dawnHour + balance.hoursPerDay - state.hoursLeft - hours
        for hour in start..<start + hours {
            var heat = state.needs.temperature
            if state.weather == .rain {
                heat -= balance.rainChillPerHour
            } else if heat < 50 {
                heat = min(50, heat + balance.sunWarmthPerHour)
            } else if !open {
                heat = max(50, heat - balance.shadeCoolPerHour)
            } else if hour >= balance.middayStart && hour < balance.middayEnd {
                heat += working ? balance.sunHeatWorking : balance.sunHeatResting
            }
            state.needs.temperature = clamp(heat, 0, 100)
            if heat > balance.sweatThreshold {
                state.needs.thirst = max(0, state.needs.thirst - balance.heatThirstPerHour)
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
        let roof = state.has(.shelter)
        for _ in 0..<hours {
            var heat = state.needs.temperature
            if state.weather == .rain {
                if !roof { heat -= balance.rainChillPerHour }
            } else if heat < 50 {
                heat = min(50, heat + balance.sunWarmthPerHour)
            } else {
                heat = max(50, heat - balance.shadeCoolPerHour)
            }
            state.needs.temperature = clamp(heat, 0, 100)
        }
    }

    /// With a fire going and a pot to put on it, stream water is boiled and becomes clean.
    private mutating func boil() -> [String] {
        guard state.fireLitToday, state.has(.clayPot), state.count(.water) > 0 else { return [] }
        let amount = state.count(.water)
        state.inventory[.cleanWater, default: 0] += amount
        state.inventory[.water] = 0
        return ["Boiled \(amount) water over the fire."]
    }

    /// Clean water first. Stream water straight from the bag can make you sick.
    private mutating func drink() -> [String] {
        var messages: [String] = []
        while state.needs.thirst <= balance.drinkThreshold && state.water > 0 {
            let clean = state.count(.cleanWater) > 0
            state.inventory[clean ? Item.cleanWater : Item.water, default: 0] -= 1
            state.needs.thirst = min(100, state.needs.thirst + balance.drinkRestore)
            if !clean {
                let chance = balance.rawWaterSicknessChance * max(0, 1 - 0.08 * Double(level(.survival)))
                if rng.chance(chance) {
                    state.needs.health -= balance.sicknessDamage
                    state.needs.fatigue = min(100, state.needs.fatigue + balance.sicknessFatigue)
                    messages.append("Unboiled water made you sick.")
                }
            }
        }
        return messages
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
        let hasShelter = state.has(.shelter)

        // Sleep
        var fatigue = state.needs.fatigue - balance.restRecoveryPerHour * Double(state.hoursLeft)
        fatigue -= hasShelter ? balance.shelterSleepRecovery : balance.sleepRecovery
        if state.weather == .rain && !hasShelter {
            fatigue += balance.rainSleepPenalty
            messages.append("Rain soaked you through the night.")
        }
        settle(hours: max(0, balance.hoursPerDay - state.hoursSpentToday))
        // The night cools you off, then takes heat. A fire and a roof keep some of it in.
        var chill = balance.nightChill
        if state.fireLitToday { chill -= balance.fireNightWarmth }
        if hasShelter { chill -= balance.shelterNightWarmth }
        if state.weather == .rain && !hasShelter { chill += balance.rainNightChill }
        state.needs.temperature = max(0, min(50, state.needs.temperature) - max(0, chill))
        if state.needs.temperature < balance.shiverThreshold {
            fatigue += balance.shiverFatigue
            messages.append("You shivered through the night.")
        }
        state.needs.fatigue = clamp(fatigue, 0, 100)

        // The rest of the day's thirst and hunger, for the hours slept through.
        wear(hours: max(0, balance.hoursPerDay - state.hoursSpentToday))
        messages += boil()
        messages += drink()

        // Eat
        let meal = state.fireLitToday ? balance.cookedMealRestore : balance.mealRestore
        while state.needs.hunger <= balance.eatThreshold && state.count(.food) > 0 {
            state.inventory[.food, default: 0] -= 1
            state.needs.hunger = min(100, state.needs.hunger + meal)
        }
        if state.count(.food) > balance.foodSpoilThreshold {
            state.inventory[.food, default: 0] -= 1
            messages.append("Some food spoiled.")
        }

        // Damage & recovery
        if state.needs.thirst <= 0 {
            state.needs.health -= balance.dehydrationDamage
            messages.append("You are dehydrated.")
        }
        if state.needs.hunger <= 0 {
            state.needs.health -= balance.starvationDamage
            messages.append("You are starving.")
        }
        if state.needs.temperature <= 0 {
            state.needs.health -= balance.hypothermiaDamage
            messages.append("The cold is in your bones.")
        }
        if state.needs.thirst > 50 && state.needs.hunger > 50 && state.needs.temperature > 25 && state.needs.temperature < 75 && state.needs.fatigue < 50 {
            state.needs.health = min(100, state.needs.health + balance.dailyRegen)
        }

        if state.needs.health <= 0 {
            let cause: DeathCause = state.needs.thirst <= 0 ? .dehydration
                : state.needs.hunger <= 0 ? .starvation : state.needs.temperature <= 0 ? .exposure : .injuries
            state.outcome = .died(day: state.day, cause: cause)
            messages.append("You did not survive the night (\(cause.rawValue)).")
            return messages
        }

        state.day += 1
        if state.day >= balance.stormDay {
            state.outcome = .storm
            messages.append("The storm arrives. No ship will come now.")
            return messages
        }

        startDay()
        messages.append("Day \(state.day) begins. Weather: \(state.weather.rawValue). Hours: \(state.hoursLeft).")
        return messages
    }

    private mutating func startDay() {
        state.weather = rng.chance(balance.rainChance) ? .rain : .clear
        if state.weather == .rain {
            // Rain is clean water. With nothing to hold it you can only drink your fill
            // while it falls; a pot keeps some for later.
            state.needs.thirst = min(100, state.needs.thirst + balance.drinkRestore)
            if state.has(.clayPot) { state.inventory[.cleanWater, default: 0] += 3 }
        }
        state.fireLitToday = false
        state.hoursSpentToday = 0
        state.actionsToday = [:]
        let lostHours = Int(state.needs.fatigue / balance.fatiguePerLostHour)
        state.hoursLeft = max(2, balance.hoursPerDay - lostHours)
    }
}
