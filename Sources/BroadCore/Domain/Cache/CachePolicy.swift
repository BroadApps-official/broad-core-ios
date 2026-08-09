import Foundation

public enum InvalidCacheEntryAction: Sendable, Equatable {
    case preserve
    case remove
}

public struct CachePolicy: Sendable, Equatable {
    public let timeToLive: TimeInterval
    public let corruptedEntryAction: InvalidCacheEntryAction
    public let schemaMismatchAction: InvalidCacheEntryAction
    public let versionMismatchAction: InvalidCacheEntryAction

    public init(
        timeToLive: TimeInterval,
        corruptedEntryAction: InvalidCacheEntryAction = .remove,
        schemaMismatchAction: InvalidCacheEntryAction = .preserve,
        versionMismatchAction: InvalidCacheEntryAction = .remove
    ) {
        precondition(
            timeToLive.isFinite && timeToLive >= 0,
            "Cache timeToLive must be finite and non-negative"
        )

        self.timeToLive = timeToLive
        self.corruptedEntryAction = corruptedEntryAction
        self.schemaMismatchAction = schemaMismatchAction
        self.versionMismatchAction = versionMismatchAction
    }
}
