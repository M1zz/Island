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
            for item in [Item.food, .wood, .fiber, .stone] where region.yields.base(for: item) > 0 {
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

        if case .rest = action {
            state.hoursLeft -= 1
            state.needs.fatigue = max(0, state.needs.fatigue - balance.restRecoveryPerHour)
            return ActionResult(success: true, messages: [])
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
            messages.append("Gathered \(amount) \(item.displayName.lowercased()) at the \(region.displayName.lowercased()).")
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
            messages.append("Fetched \(amount) water from the stream.")
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
            messages.append(success ? "The fire caught. Tonight you eat cooked food." : "The fire died out.")
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

        if state.outcome == nil, state.needs.health <= 0 {
            state.outcome = .died(day: state.day, cause: .injuries)
            messages.append("Your injuries were too much.")
        }
        state.log.append(contentsOf: messages)
        return ActionResult(success: success, messages: messages)
    }

    // MARK: - Internals

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
        state.needs.fatigue = clamp(fatigue, 0, 100)

        // Needs decay
        state.needs.thirst = max(0, state.needs.thirst - balance.thirstDecayPerDay)
        state.needs.hunger = max(0, state.needs.hunger - balance.hungerDecayPerDay)

        // Drink
        let safeWater = state.fireLitToday && state.has(.clayPot)
        while state.needs.thirst <= balance.drinkThreshold && state.count(.water) > 0 {
            state.inventory[.water, default: 0] -= 1
            state.needs.thirst = min(100, state.needs.thirst + balance.drinkRestore)
            if !safeWater {
                let chance = balance.rawWaterSicknessChance * max(0, 1 - 0.08 * Double(level(.survival)))
                if rng.chance(chance) {
                    state.needs.health -= balance.sicknessDamage
                    state.needs.fatigue = min(100, state.needs.fatigue + balance.sicknessFatigue)
                    messages.append("Unboiled water made you sick.")
                }
            }
        }

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
        if state.needs.thirst > 50 && state.needs.hunger > 50 && state.needs.fatigue < 50 {
            state.needs.health = min(100, state.needs.health + balance.dailyRegen)
        }

        if state.needs.health <= 0 {
            let cause: DeathCause = state.needs.thirst <= 0 ? .dehydration
                : state.needs.hunger <= 0 ? .starvation : .injuries
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
        if state.weather == .rain && state.has(.clayPot) {
            state.inventory[.water, default: 0] += 2
        }
        state.fireLitToday = false
        state.actionsToday = [:]
        let lostHours = Int(state.needs.fatigue / balance.fatiguePerLostHour)
        state.hoursLeft = max(2, balance.hoursPerDay - lostHours)
    }
}
