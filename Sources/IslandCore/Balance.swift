/// Every tunable number lives here so balancing never touches game logic.
/// Run `swift run island-sim` after changing anything.
public struct Balance: Codable, Sendable {
    // MARK: Time
    public var hoursPerDay = 12
    /// The storm arrives at the start of this day. Not rescued by then = game over.
    public var stormDay = 21

    // MARK: Needs (0...100)
    public var thirstDecayPerDay = 30.0
    public var hungerDecayPerDay = 15.0
    public var drinkRestore = 35.0
    public var mealRestore = 25.0
    public var cookedMealRestore = 35.0
    /// Auto-drink while thirst is at or below this.
    public var drinkThreshold = 65.0
    /// Auto-eat while hunger is at or below this.
    public var eatThreshold = 75.0
    public var dehydrationDamage = 25.0
    public var starvationDamage = 10.0
    public var dailyRegen = 5.0

    // MARK: Fatigue
    public var fatiguePerHour = 4.0
    public var exploreFatiguePerHour = 7.0
    public var sleepRecovery = 45.0
    public var shelterSleepRecovery = 65.0
    public var rainSleepPenalty = 20.0
    public var restRecoveryPerHour = 4.0
    /// Being up and about wears you down a little even when you do nothing. Only sleep restores.
    public var awakeFatiguePerHour = 1.0
    /// Every this many fatigue points costs one action hour the next day.
    public var fatiguePerLostHour = 20.0

    // MARK: Hazards
    public var rainChance = 0.25
    public var rawWaterSicknessChance = 0.12
    /// Coconuts hang high: the chance of a fall each time you climb for them, before skill.
    public var palmFallChance = 0.08
    public var sicknessDamage = 15.0
    public var sicknessFatigue = 20.0
    public var injuryDamage = 15.0
    /// Food above this count spoils by one unit per day.
    public var foodSpoilThreshold = 6

    // MARK: Skills
    /// XP needed for level L -> L+1 is `xpScale * (L + 1)^xpExponent`.
    public var xpScale = 30.0
    public var xpExponent = 1.5
    public var maxLevel = 10
    public var noveltyMultiplier = 2.0
    public var failMultiplier = 1.5
    /// Same action repeated within a day earns `repeatPenaltyBase^n` XP.
    public var repeatPenaltyBase = 0.7
    /// XP multiplier per level of difficulty above/below the player, clamped to 0.5...2.0.
    public var difficultyStep = 0.25
    /// Gathering yield bonus per skill level.
    public var yieldPerLevel = 0.2

    // MARK: Rescue
    public var signalDryWood = 30
    public var signalMinSurvival = 2
    public var signalFailureWoodLoss = 10

    // MARK: Meta progression
    /// Exploration success bonus for regions recorded in the journal from earlier runs.
    public var journalExploreBonus = 0.25

    public init() {}

    public static let standard = Balance()
}
