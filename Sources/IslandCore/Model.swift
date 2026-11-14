public enum Skill: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case foraging, crafting, exploration, survival

    public var displayName: String {
        switch self {
        case .foraging: "Foraging"
        case .crafting: "Crafting"
        case .exploration: "Exploration"
        case .survival: "Survival"
        }
    }
}

public enum Item: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    /// `water` is raw, from the stream: it can make you sick unless boiled.
    /// `cleanWater` comes from coconuts and rain and is safe as it is.
    case water, cleanWater, food, wood, dryWood, fiber, stone

    public var displayName: String {
        switch self {
        case .water: "Raw water"
        case .cleanWater: "Clean water"
        case .food: "Food"
        case .wood: "Wood"
        case .dryWood: "Dry wood"
        case .fiber: "Fiber"
        case .stone: "Stone"
        }
    }
}

/// Things you make once and keep: what stands in camp, and the tools you carry.
public enum Structure: String, CaseIterable, Codable, Sendable {
    case dryingRack, shelter, clayPot, signalFrame
    case stoneAxe, rope, torch
    /// Charcoal on bark: without it you only know where you are standing.
    case map

    /// Carried, not built.
    public var isTool: Bool {
        switch self {
        case .stoneAxe, .rope, .torch, .map: true
        case .dryingRack, .shelter, .clayPot, .signalFrame: false
        }
    }

    public var displayName: String {
        switch self {
        case .stoneAxe: "Stone axe"
        case .rope: "Rope"
        case .torch: "Torch"
        case .map: "Map"
        case .dryingRack: "Drying rack"
        case .shelter: "Shelter"
        case .clayPot: "Clay pot"
        case .signalFrame: "Signal frame"
        }
    }
}

public enum Weather: String, Codable, Sendable {
    case clear, rain
}

public struct Yields: Sendable {
    public let food: Double
    public let wood: Double
    public let fiber: Double
    public let stone: Double
    /// Coconuts: the only drink on the island before you find the stream.
    public var coconuts = 0.0

    public func base(for item: Item) -> Double {
        switch item {
        case .cleanWater: coconuts
        case .food: food
        case .wood: wood
        case .fiber: fiber
        case .stone: stone
        case .water, .dryWood: 0
        }
    }
}

public enum Region: String, CaseIterable, Codable, Sendable {
    case beach, palmGrove, stream, jungle, ridge, summit

    public var displayName: String {
        switch self {
        case .beach: "Beach"
        case .palmGrove: "Palm grove"
        case .stream: "Stream"
        case .jungle: "Jungle"
        case .ridge: "Ridge"
        case .summit: "Summit"
        }
    }

    /// Minimum exploration level to attempt discovering this region.
    /// One below `difficulty` on purpose: you can try early, fail, and learn from failing.
    public var requiredLevel: Int {
        switch self {
        case .beach, .palmGrove, .stream, .jungle: 0
        case .ridge: 1
        case .summit: 2
        }
    }

    /// What you must carry to get in at all: an axe to cut through the jungle,
    /// a rope to climb the ridge, a torch for the dark pass to the summit.
    public var requiredTool: Structure? {
        switch self {
        case .beach, .palmGrove, .stream: nil
        case .jungle: .stoneAxe
        case .ridge: .rope
        case .summit: .torch
        }
    }

    public var difficulty: Int {
        switch self {
        case .beach, .palmGrove: 0
        case .stream, .jungle: 1
        case .ridge: 2
        case .summit: 3
        }
    }

    /// Extra hours to walk there from camp (the beach).
    public var travelHours: Int {
        switch self {
        case .beach, .palmGrove: 0
        case .stream, .jungle: 1
        case .ridge: 2
        case .summit: 3
        }
    }

    public var neighbors: [Region] {
        switch self {
        case .beach: [.palmGrove, .stream]
        case .palmGrove: [.jungle]
        case .stream: [.jungle]
        case .jungle: [.ridge]
        case .ridge: [.summit]
        case .summit: []
        }
    }

    public var yields: Yields {
        switch self {
        case .beach: Yields(food: 1.5, wood: 1.5, fiber: 0, stone: 0, coconuts: 0.6)
        case .palmGrove: Yields(food: 2.5, wood: 2, fiber: 3, stone: 0, coconuts: 1)
        case .stream: Yields(food: 1.5, wood: 1, fiber: 1, stone: 1)
        case .jungle: Yields(food: 2.5, wood: 4, fiber: 2, stone: 0)
        case .ridge: Yields(food: 0, wood: 1, fiber: 0, stone: 3)
        case .summit: Yields(food: 0, wood: 0, fiber: 0, stone: 0)
        }
    }
}

public enum Recipe: String, CaseIterable, Codable, Sendable {
    case dryingRack, shelter, clayPot, signalFrame, dryWood
    case stoneAxe, rope, torch, map

    public enum Output: Sendable {
        case structure(Structure)
        case items(Item, Int)
    }

    public struct Spec: Sendable {
        public let requiredLevel: Int
        public let cost: [(Item, Int)]
        public let hours: Int
        public let baseXP: Double
        public let output: Output
        public let requiresStructure: Structure?
        public let requiresRegion: Region?
    }

    public var spec: Spec {
        switch self {
        case .dryingRack:
            Spec(requiredLevel: 0, cost: [(.wood, 6), (.fiber, 4)], hours: 2, baseXP: 30,
                 output: .structure(.dryingRack), requiresStructure: nil, requiresRegion: nil)
        case .shelter:
            Spec(requiredLevel: 1, cost: [(.wood, 12), (.fiber, 8)], hours: 4, baseXP: 40,
                 output: .structure(.shelter), requiresStructure: nil, requiresRegion: nil)
        case .clayPot:
            Spec(requiredLevel: 1, cost: [(.fiber, 2)], hours: 3, baseXP: 30,
                 output: .structure(.clayPot), requiresStructure: nil, requiresRegion: .stream)
        case .signalFrame:
            Spec(requiredLevel: 3, cost: [(.wood, 15), (.fiber, 10), (.stone, 4)], hours: 4, baseXP: 60,
                 output: .structure(.signalFrame), requiresStructure: nil, requiresRegion: .ridge)
        case .dryWood:
            Spec(requiredLevel: 0, cost: [(.wood, 3)], hours: 1, baseXP: 10,
                 output: .items(.dryWood, 3), requiresStructure: .dryingRack, requiresRegion: nil)
        case .stoneAxe:
            Spec(requiredLevel: 0, cost: [(.wood, 2), (.fiber, 2), (.stone, 1)], hours: 2, baseXP: 12,
                 output: .structure(.stoneAxe), requiresStructure: nil, requiresRegion: nil)
        case .rope:
            Spec(requiredLevel: 1, cost: [(.fiber, 6)], hours: 2, baseXP: 12,
                 output: .structure(.rope), requiresStructure: nil, requiresRegion: nil)
        case .torch:
            Spec(requiredLevel: 1, cost: [(.dryWood, 2), (.fiber, 2)], hours: 2, baseXP: 12,
                 output: .structure(.torch), requiresStructure: nil, requiresRegion: nil)
        case .map:
            Spec(requiredLevel: 0, cost: [(.wood, 2)], hours: 1, baseXP: 15,
                 output: .structure(.map), requiresStructure: nil, requiresRegion: nil)
        }
    }

    public var displayName: String {
        switch self {
        case .dryingRack: "Drying rack"
        case .shelter: "Shelter"
        case .clayPot: "Clay pot"
        case .signalFrame: "Signal frame"
        case .dryWood: "Dry wood x3"
        case .stoneAxe: "Stone axe"
        case .rope: "Rope"
        case .torch: "Torch"
        case .map: "Map"
        }
    }
}

public enum Action: Hashable, Codable, Sendable {
    case gather(Item, Region)
    case fish
    case fetchWater
    case explore(Region)
    case craft(Recipe)
    case makeFire
    case lightSignal
    /// Let one waking hour pass doing nothing useful. It costs what any hour costs:
    /// thirst, hunger, a little energy. Turning in early is the only real rest.
    case rest
    /// Rest for the remaining hours and end the day.
    case sleep
}

public enum DeathCause: String, Codable, Sendable {
    case dehydration, starvation, exposure, injuries
}

public enum Outcome: Codable, Sendable, Equatable {
    case rescued(day: Int)
    case died(day: Int, cause: DeathCause)
    case storm
}

extension Action {
    /// What the player sees on the action list.
    public var displayName: String {
        switch self {
        case let .gather(item, region): "Gather \(item.displayName.lowercased()) — \(region.displayName)"
        case .fish: "Fish at the beach"
        case .fetchWater: "Fetch water from the stream"
        case let .explore(region): "Explore toward the \(region.displayName.lowercased())"
        case let .craft(recipe): "Craft: \(recipe.displayName)"
        case .makeFire: "Make a fire"
        case .lightSignal: "Light the signal fire"
        case .rest: "Rest for an hour"
        case .sleep: "Sleep (end the day)"
        }
    }
}
