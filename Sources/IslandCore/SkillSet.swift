import Foundation

/// Use-based skills. XP is stored cumulatively; levels are derived.
public struct SkillSet: Codable, Sendable, Equatable {
    public private(set) var xp: [Skill: Double] = [:]

    public init() {}

    public static func xpToNext(level: Int, balance: Balance) -> Double {
        balance.xpScale * pow(Double(level + 1), balance.xpExponent)
    }

    public func level(_ skill: Skill, balance: Balance) -> Int {
        var remaining = xp[skill, default: 0]
        var level = 0
        while level < balance.maxLevel {
            let need = Self.xpToNext(level: level, balance: balance)
            if remaining < need { break }
            remaining -= need
            level += 1
        }
        return level
    }

    /// Progress toward the next level in 0...1.
    public func progress(_ skill: Skill, balance: Balance) -> Double {
        var remaining = xp[skill, default: 0]
        var level = 0
        while level < balance.maxLevel {
            let need = Self.xpToNext(level: level, balance: balance)
            if remaining < need { return remaining / need }
            remaining -= need
            level += 1
        }
        return 1
    }

    public mutating func add(_ amount: Double, to skill: Skill) {
        xp[skill, default: 0] += amount
    }
}
