import Foundation

public struct CacheClock: Sendable {
    private let nowProvider: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date) {
        nowProvider = now
    }

    public func now() -> Date {
        nowProvider()
    }

    public static let system = CacheClock {
        Date()
    }
}
