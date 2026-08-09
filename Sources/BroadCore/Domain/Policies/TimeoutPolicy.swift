import Foundation

public struct TimeoutPolicy: Equatable, Sendable {
    public let limit: Duration

    public init(limit: Duration) {
        precondition(limit > .zero, "Timeout limit must be greater than zero")
        self.limit = limit
    }

    public static func seconds(_ value: TimeInterval) -> TimeoutPolicy {
        precondition(value.isFinite && value > 0, "Timeout seconds must be finite and greater than zero")
        return TimeoutPolicy(limit: .milliseconds(milliseconds(from: value)))
    }

    private static func milliseconds(from seconds: TimeInterval) -> Int64 {
        let value = (seconds * 1000).rounded()
        precondition(value <= Double(Int64.max), "Timeout is too large")
        return Int64(value)
    }
}
