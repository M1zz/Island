public enum Skill: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case foraging, crafting, exploration, survival

    public var displayName: String {
        switch self {
        case .foraging: "Foraging"
        case .crafting: "Engineering"
        case .exploration: "Exploration"
        case .survival: "Survival"
        }
    }
}

public enum Item: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    /// `ice` is cut from the glacier: no use to your lungs until it is split.
    /// `air` is a canister you can breathe: from breath pods, or from ice once the electrolyzer runs.
    case ice, air, food, biomass, metal, fiber, ore

    public var displayName: String {
        switch self {
        case .ice: "Ice"
        case .air: "Air"
        case .food: "Food"
        case .biomass: "Biomass"
        case .metal: "Metal"
        case .fiber: "Fiber"
        case .ore: "Ore"
        }
    }
}

/// Things you make once and keep: what stands at the pod, the tools you carry,
/// and the three machines that turn the planet.
public enum Structure: String, CaseIterable, Codable, Sendable {
    case smelter, dome, electrolyzer
    case cutter, tether, lamp
    /// A survey sketched as you go: without it you only know where you are standing.
    case map
    /// The terraformers, in the order they must go up: heat, then water, then life.
    case warmer, thawer, seeder

    /// Carried, not built.
    public var isTool: Bool {
        switch self {
        case .cutter, .tether, .lamp, .map: true
        default: false
        }
    }

    /// How much of the planet this machine turns each day, in percent.
    public var terraformPerDay: Double {
        switch self {
        case .warmer: 4
        case .thawer: 4
        case .seeder: 6
        default: 0
        }
    }

    public static let terraformers: [Structure] = [.warmer, .thawer, .seeder]

    public var displayName: String {
        switch self {
        case .cutter: "Cutter"
        case .tether: "Tether"
        case .lamp: "Lamp"
        case .map: "Map"
        case .smelter: "Smelter"
        case .dome: "Dome"
        case .electrolyzer: "Electrolyzer"
        case .warmer: "Warmer"
        case .thawer: "Thawer"
        case .seeder: "Seeder"
        }
    }
}

public enum Weather: String, Codable, Sendable {
    case clear, storm
}

public struct Yields: Sendable {
    public let food: Double
    public let biomass: Double
    public let fiber: Double
    public let ore: Double
    /// Breath pods: the only air on the planet before you can split ice.
    public var pods = 0.0

    public func base(for item: Item) -> Double {
        switch item {
        case .air: pods
        case .food: food
        case .biomass: biomass
        case .fiber: fiber
        case .ore: ore
        case .ice, .metal: 0
        }
    }
}

public enum Region: String, CaseIterable, Codable, Sendable {
    case landing, grove, glacier, forest, rim, vent

    public var displayName: String {
        switch self {
        case .landing: "Landing site"
        case .grove: "Pod grove"
        case .glacier: "Glacier"
        case .forest: "Fungal forest"
        case .rim: "Crater rim"
        case .vent: "Vent"
        }
    }

    /// Minimum exploration level to attempt discovering this region.
    /// One below `difficulty` on purpose: you can try early, fail, and learn from failing.
    public var requiredLevel: Int {
        switch self {
        case .landing, .grove, .glacier, .forest: 0
        case .rim: 1
        case .vent: 2
        }
    }

    /// What you must carry to get in at all: a cutter for the fungal wall,
    /// a tether to climb the rim, a lamp for the dark way down to the vent.
    public var requiredTool: Structure? {
        switch self {
        case .landing, .grove, .glacier: nil
        case .forest: .cutter
        case .rim: .tether
        case .vent: .lamp
        }
    }

    /// Nothing overhead: the midday sun cooks the suit here.
    public var isOpenSky: Bool {
        switch self {
        case .landing, .rim, .vent: true
        case .grove, .glacier, .forest: false
        }
    }

    public var difficulty: Int {
        switch self {
        case .landing, .grove: 0
        case .glacier, .forest: 1
        case .rim: 2
        case .vent: 3
        }
    }

    /// Extra hours to walk there from the pod.
    public var travelHours: Int {
        switch self {
        case .landing, .grove: 0
        case .glacier, .forest: 1
        case .rim: 2
        case .vent: 3
        }
    }

    public var neighbors: [Region] {
        switch self {
        case .landing: [.grove, .glacier]
        case .grove: [.forest]
        case .glacier: [.forest]
        case .forest: [.rim]
        case .rim: [.vent]
        case .vent: []
        }
    }

    public var yields: Yields {
        switch self {
        case .landing: Yields(food: 1.5, biomass: 1.5, fiber: 0, ore: 0, pods: 0.6)
        case .grove: Yields(food: 2.5, biomass: 2, fiber: 3, ore: 0, pods: 1)
        case .glacier: Yields(food: 1.5, biomass: 1, fiber: 1, ore: 2)
        case .forest: Yields(food: 2.5, biomass: 4, fiber: 2, ore: 0)
        case .rim: Yields(food: 0, biomass: 1, fiber: 0, ore: 4)
        case .vent: Yields(food: 0, biomass: 0, fiber: 0, ore: 0)
        }
    }
}

public enum Recipe: String, CaseIterable, Codable, Sendable {
    case smelter, dome, electrolyzer, metal
    case cutter, tether, lamp, map
    case warmer, thawer, seeder

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
        case .smelter:
            Spec(requiredLevel: 0, cost: [(.biomass, 6), (.fiber, 4)], hours: 2, baseXP: 30,
                 output: .structure(.smelter), requiresStructure: nil, requiresRegion: nil)
        case .dome:
            Spec(requiredLevel: 1, cost: [(.biomass, 12), (.fiber, 8)], hours: 4, baseXP: 40,
                 output: .structure(.dome), requiresStructure: nil, requiresRegion: nil)
        case .electrolyzer:
            Spec(requiredLevel: 1, cost: [(.metal, 2), (.fiber, 2)], hours: 3, baseXP: 30,
                 output: .structure(.electrolyzer), requiresStructure: nil, requiresRegion: .glacier)
        case .metal:
            Spec(requiredLevel: 0, cost: [(.ore, 3)], hours: 1, baseXP: 10,
                 output: .items(.metal, 3), requiresStructure: .smelter, requiresRegion: nil)
        case .cutter:
            Spec(requiredLevel: 0, cost: [(.biomass, 2), (.fiber, 2), (.ore, 1)], hours: 2, baseXP: 12,
                 output: .structure(.cutter), requiresStructure: nil, requiresRegion: nil)
        case .tether:
            Spec(requiredLevel: 1, cost: [(.fiber, 6)], hours: 2, baseXP: 12,
                 output: .structure(.tether), requiresStructure: nil, requiresRegion: nil)
        case .lamp:
            Spec(requiredLevel: 1, cost: [(.metal, 2), (.fiber, 2)], hours: 2, baseXP: 12,
                 output: .structure(.lamp), requiresStructure: nil, requiresRegion: nil)
        case .map:
            Spec(requiredLevel: 0, cost: [(.biomass, 2)], hours: 1, baseXP: 15,
                 output: .structure(.map), requiresStructure: nil, requiresRegion: nil)
        case .warmer:
            Spec(requiredLevel: 1, cost: [(.metal, 6), (.biomass, 4)], hours: 3, baseXP: 50,
                 output: .structure(.warmer), requiresStructure: .smelter, requiresRegion: nil)
        case .thawer:
            Spec(requiredLevel: 2, cost: [(.metal, 9), (.fiber, 6)], hours: 3, baseXP: 55,
                 output: .structure(.thawer), requiresStructure: .warmer, requiresRegion: .glacier)
        case .seeder:
            Spec(requiredLevel: 3, cost: [(.metal, 12), (.biomass, 10), (.fiber, 6)], hours: 4, baseXP: 60,
                 output: .structure(.seeder), requiresStructure: .thawer, requiresRegion: .vent)
        }
    }

    public var displayName: String {
        switch self {
        case .metal: "Metal x3"
        default:
            if case let .structure(structure) = spec.output { structure.displayName } else { rawValue }
        }
    }
}

public enum Action: Hashable, Codable, Sendable {
    case gather(Item, Region)
    case cutIce
    case explore(Region)
    case craft(Recipe)
    /// Burn biomass for a day's heat and power: warm food, a warm night, and the electrolyzer runs.
    case lightBurner
    /// Let one waking hour pass doing nothing useful. It costs what any hour costs:
    /// air, hunger, a little energy. Turning in early is the only real rest.
    /// `shaded` is whether you spend it out of the sun.
    case rest(shaded: Bool)
    /// Rest for the remaining hours and end the day.
    case sleep
}

public enum DeathCause: String, Codable, Sendable {
    case suffocation, starvation, exposure, heatstroke, injuries
}

public enum Outcome: Codable, Sendable, Equatable {
    /// You took the helmet off and breathed.
    case habitable(day: Int)
    case died(day: Int, cause: DeathCause)
    /// The long winter came before the planet could carry you through it.
    case winter
}

extension Action {
    /// What the player sees on the action list.
    public var displayName: String {
        switch self {
        case let .gather(item, region): "Gather \(item.displayName.lowercased()) — \(region.displayName)"
        case .cutIce: "Cut ice at the glacier"
        case let .explore(region): "Explore toward the \(region.displayName.lowercased())"
        case let .craft(recipe): "Build: \(recipe.displayName)"
        case .lightBurner: "Light the burner"
        case .rest: "Rest for an hour"
        case .sleep: "Sleep (end the day)"
        }
    }
}
