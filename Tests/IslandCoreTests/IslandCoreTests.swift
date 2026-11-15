import XCTest
@testable import IslandCore

final class IslandCoreTests: XCTestCase {
    func testRNGIsDeterministic() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testRNGIsSplitMix64() {
        var rng = SplitMix64(seed: 1)
        XCTAssertEqual(rng.next(), 0x910A_2DEC_8902_5CC1)
    }

    func testLevelThresholds() {
        let balance = Balance.standard
        var skills = SkillSet()
        XCTAssertEqual(skills.level(.crafting, balance: balance), 0)
        skills.add(SkillSet.xpToNext(level: 0, balance: balance), to: .crafting)
        XCTAssertEqual(skills.level(.crafting, balance: balance), 1)
        skills.add(SkillSet.xpToNext(level: 1, balance: balance) - 0.01, to: .crafting)
        XCTAssertEqual(skills.level(.crafting, balance: balance), 1)
    }

    func testNothingTurnsAtStart() {
        let engine = GameEngine(seed: 1)
        XCTAssertEqual(engine.terraformPerDay, 0)
        XCTAssertTrue(engine.terraformChecklist.allSatisfy { !$0.done })
        XCTAssertFalse(engine.canPerform(.craft(.warmer)))
    }

    func testVentNeedsExplorationLevel() {
        let engine = GameEngine(seed: 1)
        XCTAssertFalse(engine.canPerform(.explore(.vent)))
    }

    func testThePlanetOnlyTurnsWithMachines() {
        // The winner always has all three; nobody wins without the planet at 100.
        var bot = PlannerBot()
        for seed: UInt64 in 1...80 {
            let state = simulate(seed: seed, bot: &bot)
            XCTAssertEqual(state.terraform > 0, state.has(.warmer), "seed \(seed)")
            if case .habitable = state.outcome { XCTAssertEqual(state.terraform, 100) }
        }
    }

    func testRegionsBehindToolsStayShut() {
        // However skilled, the fungal forest needs a cutter.
        let engine = GameEngine(seed: 1)
        XCTAssertTrue(engine.canPerform(.explore(.grove)))
        var bot = PlannerBot()
        for seed: UInt64 in 1...50 {
            let state = simulate(seed: seed, bot: &bot)
            for region in Region.allCases where state.discovered.contains(region) {
                if let tool = region.requiredTool { XCTAssertTrue(state.has(tool), "\(region) without \(tool)") }
            }
        }
    }

    func testSameSeedSameGame() {
        var botA = PlannerBot()
        var botB = PlannerBot()
        let a = simulate(seed: 7, bot: &botA)
        let b = simulate(seed: 7, bot: &botB)
        XCTAssertEqual(a.outcome, b.outcome)
        XCTAssertEqual(a.day, b.day)
    }

    func testSpecialistNeverTurnsThePlanet() {
        for seed in 1...50 {
            var bot = ForagerBot()
            let state = simulate(seed: UInt64(seed), bot: &bot)
            if case .habitable = state.outcome {
                XCTFail("Forager should never win (seed \(seed))")
            }
        }
    }

    func testJournalRecordsRun() {
        var bot = PlannerBot()
        let state = simulate(seed: 3, bot: &bot)
        var journal = Journal()
        journal.record(state)
        XCTAssertEqual(journal.runs, 1)
        XCTAssertTrue(journal.knownRegions.isSuperset(of: state.discovered))
    }

    /// Balance guard: if a change makes the game trivial or impossible, this fails.
    func testPlannerWinRateStaysInBand() {
        var rescued = 0
        let games = 300
        for seed in 1...games {
            var bot = PlannerBot()
            if case .habitable = simulate(seed: UInt64(seed), bot: &bot).outcome { rescued += 1 }
        }
        let rate = Double(rescued) / Double(games)
        XCTAssertGreaterThan(rate, 0.35, "Too hard: planner win rate \(rate)")
        XCTAssertLessThan(rate, 0.80, "Too easy: planner win rate \(rate)")
    }

    func testMiddaySunBringsHeatstrokeAndShadeDoesNot() {
        // Find a dry first day, then stand in the open until evening.
        let seed = (1...50).first { GameEngine(seed: $0).state.weather == .clear }!
        var sun = GameEngine(seed: seed)
        var shade = GameEngine(seed: seed)
        while sun.state.hoursLeft > 3 { sun.perform(.rest(shaded: false)) }
        while shade.state.hoursLeft > 3 { shade.perform(.rest(shaded: true)) }
        XCTAssertGreaterThan(sun.state.needs.temperature, 75)
        XCTAssertEqual(shade.state.needs.temperature, 50)
        XCTAssertLessThan(sun.state.needs.oxygen, shade.state.needs.oxygen)
    }

    func testNeedsFallThroughTheDay() {
        var engine = GameEngine(seed: 7)
        let morning = engine.state.needs
        engine.perform(.rest(shaded: true))
        XCTAssertLessThan(engine.state.needs.oxygen, morning.oxygen)
        XCTAssertLessThan(engine.state.needs.hunger, morning.hunger)
        XCTAssertGreaterThan(engine.state.needs.fatigue, morning.fatigue)
    }

    func testStayingUpCostsTheSameFoodAndAirButNoRest() {
        var up = GameEngine(seed: 7)
        var early = GameEngine(seed: 7)
        while up.state.hoursLeft > 0 { up.perform(.rest(shaded: true)) }
        up.perform(.sleep)
        early.perform(.sleep)
        // A day is a day for air and hunger, however it was spent.
        XCTAssertEqual(up.state.needs.oxygen, early.state.needs.oxygen, accuracy: 0.001)
        XCTAssertEqual(up.state.needs.hunger, early.state.needs.hunger, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(up.state.needs.fatigue, early.state.needs.fatigue)
    }
}
