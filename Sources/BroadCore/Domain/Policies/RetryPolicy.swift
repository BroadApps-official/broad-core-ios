import Foundation

public struct RetryPolicy: Equatable, Sendable {
    public static let none = RetryPolicy(delays: [])

    public let delays: [Duration]

    public init(delays: [Duration]) {
        precondition(delays.allSatisfy { $0 >= .zero }, "Retry delays must not be negative")
        self.delays = delays
    }

    public static func fixed(retryCount: Int, delay: TimeInterval) -> RetryPolicy {
        precondition(retryCount >= 0, "Retry count must not be negative")
        precondition(delay.isFinite && delay >= 0, "Retry delay must be finite and non-negative")

        let duration = Duration.milliseconds(milliseconds(from: delay))
        return RetryPolicy(delays: Array(repeating: duration, count: retryCount))
    }

    public static func exponential(
        retryCount: Int,
        initialDelay: TimeInterval,
        multiplier: Double = 2,
        maximumDelay: TimeInterval
    ) -> RetryPolicy {
        precondition(retryCount >= 0, "Retry count must not be negative")
        precondition(initialDelay.isFinite && initialDelay >= 0, "Initial delay must be finite and non-negative")
        precondition(multiplier.isFinite && multiplier >= 1, "Retry multiplier must be finite and at least one")
        precondition(maximumDelay.isFinite && maximumDelay >= 0, "Maximum delay must be finite and non-negative")

        var currentDelay = min(initialDelay, maximumDelay)
        var delays: [Duration] = []
        delays.reserveCapacity(retryCount)

        for _ in 0 ..< retryCount {
            delays.append(.milliseconds(milliseconds(from: currentDelay)))
            currentDelay = min(currentDelay * multiplier, maximumDelay)
        }

        return RetryPolicy(delays: delays)
    }

    private static func milliseconds(from seconds: TimeInterval) -> Int64 {
        let value = (seconds * 1000).rounded()
        precondition(value <= Double(Int64.max), "Retry delay is too large")
        return Int64(value)
    }
}
