/// Every tunable number lives here so balancing never touches game logic.
/// Run `swift run island-sim` after changing anything.
public struct Balance: Codable, Sendable {
    // MARK: Time
    public var hoursPerDay = 12
    /// The long winter arrives at the start of this day. Planet not habitable by then = game over.
    public var winterDay = 24

    // MARK: Needs (0...100)
    public var oxygenDecayPerDay = 30.0
    public var hungerDecayPerDay = 15.0
    public var breathRestore = 35.0
    public var mealRestore = 25.0
    public var cookedMealRestore = 35.0
    /// Open a canister while the tank is at or below this.
    public var breatheThreshold = 65.0
    /// Auto-eat while hunger is at or below this.
    public var eatThreshold = 75.0
    public var suffocationDamage = 25.0
    public var starvationDamage = 10.0
    public var dailyRegen = 5.0

    // MARK: Fatigue
    public var fatiguePerHour = 4.0
    public var exploreFatiguePerHour = 7.0
    public var sleepRecovery = 45.0
    public var shelterSleepRecovery = 65.0
    public var stormSleepPenalty = 20.0

    // Body temperature (50 is right)
    /// The day starts at this hour of the clock; midday is when the sun does harm.
    public var dawnHour = 6
    public var middayStart = 10
    public var middayEnd = 15
    /// Lost each waking hour out in a storm.
    public var stormChillPerHour = 1.0
    /// Regained each dry hour while cold.
    public var sunWarmthPerHour = 2.0
    /// Regained at once, while cold, when a fire catches.
    public var fireWarmth = 15.0
    /// Lost over a night in the open, before anything that helps or hurts.
    public var nightChill = 10.0
    public var fireNightWarmth = 7.5
    public var shelterNightWarmth = 5.0
    /// Extra lost on a stormy night with no dome.
    public var stormNightChill = 5.0
    /// Below this you shiver instead of sleeping.
    public var shiverThreshold = 20.0
    public var shiverFatigue = 10.0
    public var hypothermiaDamage = 20.0
    /// Gained each midday hour under open sky, working or just standing there.
    public var sunHeatWorking = 10.0
    public var sunHeatResting = 6.0
    /// Shed each hour in the shade, and at once at the water.
    public var shadeCoolPerHour = 6.0
    public var waterCool = 10.0
    /// Above this the suit works to cool you: extra air each hour.
    public var sweatThreshold = 70.0
    public var heatAirPerHour = 1.5
    public var heatstrokeDamage = 20.0
    public var heatstrokeFatigue = 20.0
    public var restRecoveryPerHour = 4.0
    /// Being up and about wears you down a little even when you do nothing. Only sleep restores.
    public var awakeFatiguePerHour = 1.0
    /// Every this many fatigue points costs one action hour the next day.
    public var fatiguePerLostHour = 20.0

    // MARK: Hazards
    public var stormChance = 0.25
    /// Breath pods hang high: the chance of a fall each time you climb for them, before skill.
    public var podFallChance = 0.08
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

    // MARK: Terraforming (as the planet turns from 0 to 100)
    /// Share of the suit's air use the open air takes over by the end.
    public var terraformAirRelief = 0.6
    /// Night chill taken off by the end.
    public var terraformNightWarmth = 6.0
    /// Extra food and biomass by the end, as a share of the base yield.
    public var terraformGrowth = 1.0

    // MARK: Meta progression
    /// Exploration success bonus for regions recorded in the journal from earlier runs.
    public var journalExploreBonus = 0.25

    public init() {}

    public static let standard = Balance()
}
