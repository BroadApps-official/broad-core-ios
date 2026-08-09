public enum BroadLogLevel: String, CaseIterable, Equatable, Sendable {
    case debug
    case info
    case warning
    case error
}

public enum BroadLogCategory: String, CaseIterable, Equatable, Sendable {
    case bootstrap
    case cache
    case networking
    case monetization
    case paywall
    case purchase
    case ruBilling
    case experiments
}

public enum BroadLogBootstrapState: String, Equatable, Sendable {
    case idle
    case starting
    case ready
    case degraded
    case failed
}

public enum BroadLogBootstrapStepKind: String, Equatable, Sendable {
    case critical
    case background
}

public enum BroadLogBootstrapBackgroundOutcome: String, Equatable, Sendable {
    case completed
    case degraded
}

public enum BroadLogCacheReadResult: String, Equatable, Sendable {
    case fresh
    case stale
    case notFound
    case corrupted
    case schemaMismatch
    case versionMismatch
}

public enum BroadLogCacheOperation: String, Equatable, Sendable {
    case read
    case write
    case remove
    case cleanup
}

public enum BroadLogCacheFailure: String, Equatable, Sendable {
    case storage
    case encoding
    case invalidTimestamp
    case valueTooLarge
}

public enum BroadLogEvent: Equatable, Sendable {
    case bootstrapRunStarted(criticalStepCount: Int, backgroundStepCount: Int)
    case bootstrapRunJoined
    case bootstrapRetryRequested
    case bootstrapRunCancelled
    case bootstrapStateChanged(BroadLogBootstrapState)
    case bootstrapBackgroundStarted(stepCount: Int)
    case bootstrapBackgroundFinished(BroadLogBootstrapBackgroundOutcome)
    case bootstrapStepStarted(index: Int, kind: BroadLogBootstrapStepKind)
    case bootstrapStepRetried(index: Int, kind: BroadLogBootstrapStepKind, retryCount: Int)
    case bootstrapStepCompleted(index: Int, kind: BroadLogBootstrapStepKind, attemptCount: Int)
    case bootstrapStepDegraded(
        index: Int,
        kind: BroadLogBootstrapStepKind,
        attemptCount: Int,
        errorKind: AppError.Kind
    )
    case bootstrapStepFailed(
        index: Int,
        kind: BroadLogBootstrapStepKind,
        attemptCount: Int,
        errorKind: AppError.Kind
    )
    case bootstrapStepTimedOut(index: Int, kind: BroadLogBootstrapStepKind)
    case bootstrapStepCancelled(index: Int, kind: BroadLogBootstrapStepKind)
    case cacheReadCompleted(BroadLogCacheReadResult)
    case cacheOperationCompleted(BroadLogCacheOperation)
    case cacheOperationFailed(operation: BroadLogCacheOperation, failure: BroadLogCacheFailure)

    public var category: BroadLogCategory {
        switch self {
        case .bootstrapRunStarted,
             .bootstrapRunJoined,
             .bootstrapRetryRequested,
             .bootstrapRunCancelled,
             .bootstrapStateChanged,
             .bootstrapBackgroundStarted,
             .bootstrapBackgroundFinished,
             .bootstrapStepStarted,
             .bootstrapStepRetried,
             .bootstrapStepCompleted,
             .bootstrapStepDegraded,
             .bootstrapStepFailed,
             .bootstrapStepTimedOut,
             .bootstrapStepCancelled:
            .bootstrap
        case .cacheReadCompleted, .cacheOperationCompleted, .cacheOperationFailed:
            .cache
        }
    }

    public var level: BroadLogLevel {
        switch self {
        case .bootstrapRunJoined, .bootstrapRunCancelled, .bootstrapStepStarted, .bootstrapStepCancelled:
            .debug
        case .bootstrapRunStarted,
             .bootstrapRetryRequested,
             .bootstrapBackgroundStarted,
             .bootstrapStepCompleted,
             .cacheOperationCompleted:
            .info
        case let .bootstrapStateChanged(state):
            state.logLevel
        case let .bootstrapBackgroundFinished(outcome):
            outcome == .degraded ? .warning : .info
        case .bootstrapStepRetried, .bootstrapStepDegraded:
            .warning
        case .bootstrapStepFailed, .bootstrapStepTimedOut, .cacheOperationFailed:
            .error
        case let .cacheReadCompleted(result):
            result.logLevel
        }
    }

    public var name: String {
        switch self {
        case .bootstrapRunStarted: "bootstrap.run.started"
        case .bootstrapRunJoined: "bootstrap.run.joined"
        case .bootstrapRetryRequested: "bootstrap.retry.requested"
        case .bootstrapRunCancelled: "bootstrap.run.cancelled"
        case .bootstrapStateChanged: "bootstrap.state.changed"
        case .bootstrapBackgroundStarted: "bootstrap.background.started"
        case .bootstrapBackgroundFinished: "bootstrap.background.finished"
        case .bootstrapStepStarted: "bootstrap.step.started"
        case .bootstrapStepRetried: "bootstrap.step.retried"
        case .bootstrapStepCompleted: "bootstrap.step.completed"
        case .bootstrapStepDegraded: "bootstrap.step.degraded"
        case .bootstrapStepFailed: "bootstrap.step.failed"
        case .bootstrapStepTimedOut: "bootstrap.step.timed-out"
        case .bootstrapStepCancelled: "bootstrap.step.cancelled"
        case .cacheReadCompleted: "cache.read.completed"
        case .cacheOperationCompleted: "cache.operation.completed"
        case .cacheOperationFailed: "cache.operation.failed"
        }
    }
}

private extension BroadLogBootstrapState {
    var logLevel: BroadLogLevel {
        switch self {
        case .idle:
            .debug
        case .starting, .ready:
            .info
        case .degraded:
            .warning
        case .failed:
            .error
        }
    }
}

private extension BroadLogCacheReadResult {
    var logLevel: BroadLogLevel {
        switch self {
        case .fresh:
            .debug
        case .notFound:
            .info
        case .stale, .corrupted, .schemaMismatch, .versionMismatch:
            .warning
        }
    }
}
