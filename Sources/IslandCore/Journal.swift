import Foundation

/// What survives between castaways. Skills reset every run; knowledge does not.
public struct Journal: Codable, Sendable, Equatable {
    public var runs = 0
    public var rescues = 0
    public var bestRescueDay: Int?
    public var knownRegions: Set<Region> = [.beach]
    public var notes: [String] = []

    public init() {}

    public mutating func record(_ state: GameState) {
        runs += 1
        knownRegions.formUnion(state.discovered)
        switch state.outcome {
        case let .rescued(day):
            rescues += 1
            bestRescueDay = min(bestRescueDay ?? day, day)
            notes.append("Castaway #\(runs) was rescued on day \(day).")
        case let .died(day, cause):
            notes.append("Castaway #\(runs) died of \(cause.rawValue) on day \(day).")
        case .storm:
            notes.append("Castaway #\(runs) was lost to the storm.")
        case nil:
            break
        }
    }

    // MARK: Persistence

    public static func load(from url: URL) -> Journal {
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(Journal.self, from: data)
        else { return Journal() }
        return journal
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
