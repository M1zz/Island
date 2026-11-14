import Foundation
import IslandCore

// Text prototype. Usage: swift run island [seed]
// The journal persists between runs at ~/.island/journal.json.

let journalURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".island/journal.json")
var journal = Journal.load(from: journalURL)
let seed = CommandLine.arguments.dropFirst().first.flatMap(UInt64.init) ?? UInt64.random(in: 1...UInt64.max)
var engine = GameEngine(seed: seed, journal: journal)

func describe(_ action: Action, _ engine: GameEngine) -> String {
    if case .sleep = action { return action.displayName }
    return "\(action.displayName) [\(engine.hours(for: action))h]"
}

func bar(_ value: Double) -> String {
    let filled = Int((value / 10).rounded())
    return String(repeating: "█", count: max(0, filled)) + String(repeating: "·", count: max(0, 10 - filled))
}

func printStatus(_ engine: GameEngine) {
    let s = engine.state
    print("""

    ─── Day \(s.day)/\(engine.balance.stormDay - 1)  ·  \(s.weather.rawValue)  ·  \(s.hoursLeft)h left ───
    Thirst  \(bar(s.needs.thirst)) \(Int(s.needs.thirst))    Hunger \(bar(s.needs.hunger)) \(Int(s.needs.hunger))
    Fatigue \(bar(s.needs.fatigue)) \(Int(s.needs.fatigue))    Health \(bar(s.needs.health)) \(Int(s.needs.health))
    """)
    let skills = Skill.allCases.map { skill in
        "\(skill.displayName) \(engine.level(skill)) (\(Int(s.skills.progress(skill, balance: engine.balance) * 100))%)"
    }
    print("Skills: " + skills.joined(separator: " · "))
    let items = Item.allCases.filter { s.count($0) > 0 }.map { "\($0.displayName) \(s.count($0))" }
    print("Items:  " + (items.isEmpty ? "nothing" : items.joined(separator: ", ")))
    let built = Structure.allCases.filter(s.has).map(\.displayName)
    if !built.isEmpty { print("Built:  " + built.joined(separator: ", ")) }
    let known = Region.allCases.filter(s.discovered.contains).map(\.displayName)
    print("Map:    " + known.joined(separator: " → "))
    print("Rescue: " + engine.rescueChecklist.map { ($0.done ? "☑ " : "☐ ") + $0.label }.joined(separator: "  "))
}

print("""
UNKNOWN ISLAND — castaway #\(journal.runs + 1)
Survive. Learn. Signal for rescue before the storm on day \(engine.balance.stormDay).
""")
for note in journal.notes.suffix(3) {
    print("📓 \(note)")
}
for line in engine.state.log { print(line) }

while !engine.state.isOver {
    printStatus(engine)
    let actions = engine.availableActions
    for (index, action) in actions.enumerated() {
        print("  \(index + 1). \(describe(action, engine))")
    }
    print("> ", terminator: "")
    guard let input = readLine() else { break }
    guard let choice = Int(input.trimmingCharacters(in: .whitespaces)),
          actions.indices.contains(choice - 1)
    else {
        print("Pick a number from the list.")
        continue
    }
    let result = engine.perform(actions[choice - 1])
    for message in result.messages { print("• \(message)") }
}

journal.record(engine.state)
do {
    try journal.save(to: journalURL)
    print("\nYour journal was updated (\(journal.runs) castaways so far).")
} catch {
    print("\nCould not save the journal: \(error)")
}
