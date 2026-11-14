public struct Needs: Codable, Sendable, Equatable {
    public var thirst = 100.0
    public var hunger = 100.0
    public var fatigue = 0.0
    public var health = 100.0
}

public struct GameState: Codable, Sendable {
    public var day = 1
    public var hoursLeft: Int
    public var weather: Weather = .clear
    public var needs = Needs()
    /// What washed ashore with you: a bottle of clean water and a little food.
    public var inventory: [Item: Int] = [.cleanWater: 3, .food: 3]
    public var skills = SkillSet()
    public var discovered: Set<Region> = [.beach]
    public var structures: Set<Structure> = []
    public var fireLitToday = false
    /// How many times each action key was used today (for the repeat penalty).
    public var actionsToday: [String: Int] = [:]
    /// Action keys ever performed this run (for the novelty bonus).
    public var firstTimes: Set<String> = []
    public var outcome: Outcome?
    public var log: [String] = []

    public init(hoursPerDay: Int) {
        hoursLeft = hoursPerDay
    }

    public var isOver: Bool { outcome != nil }

    public func count(_ item: Item) -> Int {
        inventory[item, default: 0]
    }

    /// Everything drinkable, clean or not.
    public var water: Int { count(.water) + count(.cleanWater) }

    public func has(_ structure: Structure) -> Bool {
        structures.contains(structure)
    }
}
