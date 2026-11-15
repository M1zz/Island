public struct Needs: Codable, Sendable, Equatable {
    /// What is left in the suit's tank.
    public var oxygen = 100.0
    public var hunger = 100.0
    public var fatigue = 0.0
    /// Body temperature: 50 is right, 0 is hypothermia, 100 is heatstroke.
    /// Storms and bare nights pull it down; the midday sun on the suit pushes it up; shade, ice and the burner bring it back.
    public var temperature = 50.0
    public var health = 100.0
}

public struct GameState: Codable, Sendable {
    public var day = 1
    public var hoursLeft: Int
    public var weather: Weather = .clear
    public var needs = Needs()
    /// What came out of the pod with you: three canisters of air and a little food.
    public var inventory: [Item: Int] = [.air: 3, .food: 3]
    public var skills = SkillSet()
    public var discovered: Set<Region> = [.landing]
    public var structures: Set<Structure> = []
    public var burnerLit = false
    /// How far the planet has turned, 0...100. At 100 you can breathe it.
    public var terraform = 0.0
    /// Waking hours used so far today; air and hunger have already been charged for these.
    public var hoursSpentToday = 0
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

    public func has(_ structure: Structure) -> Bool {
        structures.contains(structure)
    }
}
