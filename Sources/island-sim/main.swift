import Foundation
import IslandCore

// Usage: swift run -c release island-sim [games=1000]

let games = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 1000
let balance = Balance.standard

struct Stats {
    var habitable = 0
    var winter = 0
    var deaths: [DeathCause: Int] = [:]
    var days: [Int] = []
    var levels: [Skill: Int] = [:]

    mutating func add(_ state: GameState, balance: Balance) {
        switch state.outcome {
        case let .habitable(day):
            habitable += 1
            days.append(day)
        case let .died(_, cause):
            deaths[cause, default: 0] += 1
        case .winter, nil:
            winter += 1
        }
        for skill in Skill.allCases {
            levels[skill, default: 0] += state.skills.level(skill, balance: balance)
        }
    }

    func line(name: String, games: Int) -> String {
        func pct(_ n: Int) -> String { String(format: "%5.1f%%", Double(n) / Double(games) * 100) }
        let died = deaths.values.reduce(0, +)
        let causes = deaths.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " ")
        let avgDay = days.isEmpty ? "-"
            : String(format: "%.1f", Double(days.reduce(0, +)) / Double(days.count))
        let lv = Skill.allCases.map {
            "\($0.rawValue.prefix(3))=\(String(format: "%.1f", Double(levels[$0, default: 0]) / Double(games)))"
        }.joined(separator: " ")
        let name = name.padding(toLength: 8, withPad: " ", startingAt: 0)
        return "\(name) habitable \(pct(habitable))  winter \(pct(winter))  died \(pct(died)) [\(causes)]  avg day \(avgDay)  lv \(lv)"
    }
}

func run<B: Bot>(_ makeBot: () -> B, veteran: Bool) -> String {
    var stats = Stats()
    var journal = Journal()
    if veteran { journal.knownRegions = Set(Region.allCases) }
    var name = ""
    for seed in 1...games {
        var bot = makeBot()
        name = bot.name
        let state = simulate(seed: UInt64(seed), bot: &bot, balance: balance, journal: journal)
        stats.add(state, balance: balance)
    }
    return stats.line(name: name, games: games)
}

for veteran in [false, true] {
    print(veteran ? "== veteran (journal knows every region) ==" : "== fresh castaway ==")
    print(run(RandomBot.init, veteran: veteran))
    print(run(ForagerBot.init, veteran: veteran))
    print(run(PlannerBot.init, veteran: veteran))
}
