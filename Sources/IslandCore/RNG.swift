/// Deterministic, seedable RNG (SplitMix64).
/// All game randomness goes through `unit()` so runs are reproducible
/// and the balancing simulator can replay exact seeds.
public struct SplitMix64: RandomNumberGenerator, Codable, Sendable {
    public var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    public mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    /// Uniform integer in [0, upperBound).
    public mutating func index(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return min(Int(unit() * Double(upperBound)), upperBound - 1)
    }
}

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}
