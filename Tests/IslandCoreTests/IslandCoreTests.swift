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

    func testRNGMatchesPythonMirror() {
        // Same value the Python balancing mirror (balance/island.py) produces for seed 1.
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

    func testSignalLockedAtStart() {
        let engine = GameEngine(seed: 1)
        XCTAssertFalse(engine.canPerform(.lightSignal))
        XCTAssertTrue(engine.rescueChecklist.allSatisfy { !$0.done })
    }

    func testSummitNeedsExplorationLevel() {
        let engine = GameEngine(seed: 1)
        XCTAssertFalse(engine.canPerform(.explore(.summit)))
    }

    func testRegionsBehindToolsStayShut() {
        // However skilled, the jungle needs an axe.
        let engine = GameEngine(seed: 1)
        XCTAssertTrue(engine.canPerform(.explore(.palmGrove)))
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

    func testSpecialistNeverGetsRescued() {
        for seed in 1...50 {
            var bot = ForagerBot()
            let state = simulate(seed: UInt64(seed), bot: &bot)
            if case .rescued = state.outcome {
                XCTFail("Forager should never be rescued (seed \(seed))")
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
    func testPlannerRescueRateStaysInBand() {
        var rescued = 0
        let games = 300
        for seed in 1...games {
            var bot = PlannerBot()
            if case .rescued = simulate(seed: UInt64(seed), bot: &bot).outcome { rescued += 1 }
        }
        let rate = Double(rescued) / Double(games)
        XCTAssertGreaterThan(rate, 0.35, "Too hard: planner rescue rate \(rate)")
        XCTAssertLessThan(rate, 0.80, "Too easy: planner rescue rate \(rate)")
    }

    func testRestingBeforeSleepMatchesSleepingEarly() {
        var rested = GameEngine(seed: 7)
        var direct = GameEngine(seed: 7)
        rested.perform(.gather(.wood, .beach))
        direct.perform(.gather(.wood, .beach))
        while rested.state.hoursLeft > 0 { rested.perform(.rest) }
        rested.perform(.sleep)
        direct.perform(.sleep)
        XCTAssertEqual(rested.state.needs, direct.state.needs)
        XCTAssertEqual(rested.state.hoursLeft, direct.state.hoursLeft)
    }
}
