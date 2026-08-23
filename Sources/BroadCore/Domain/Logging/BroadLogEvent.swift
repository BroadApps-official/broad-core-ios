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
    case input
    case backend
    case flow
    case tokens
    case analytics
    case userInterface = "ui"
    case blocked
    case pass
}

public enum BroadLogFlowStage: String, Equatable, Sendable {
    case launch
    case onboarding
    case initialPaywall = "initial-paywall"
    case specialOffer = "special-offer"
    case tokenPaywall = "token-paywall"
    case main
}

public enum BroadLogBackendCapability: String, Equatable, Sendable {
    case account
    case content
    case history
    case monetization
    case tokenBalance = "token-balance"
    case tokenFulfillment = "token-fulfillment"
}

public enum BroadLogBlocker: String, Equatable, Sendable {
    case sourceUnavailable = "source-unavailable"
    case backendContractMissing = "backend-contract-missing"
    case designMismatch = "design-mismatch"
    case buildFailed = "build-failed"
}

public enum BroadLogVerificationScope: String, Equatable, Sendable {
    case functional
    case visual
    case full
}

public enum BroadLogRemoteFeatureFixtureScenario: String, Equatable, Sendable {
    case specialOfferEnabled = "special-offer-enabled"
    case specialOfferDisabled = "special-offer-disabled"
    case specialOfferPlatformCache = "special-offer-platform-cache"
    case specialOfferMainFallback = "special-offer-main-fallback"
    case specialOfferTimed = "special-offer-timed"
    case ruPayProviderEnabled = "ru-pay-provider-enabled"
    case ruPayPlatformCache = "ru-pay-platform-cache"
}

public enum BroadLogRemoteFeatureResolution: String, Equatable, Sendable {
    case presented
    case unavailable
    case expired
    case cooldown
}

public enum BroadLogPlacement: String, Equatable, Sendable {
    case main
    case specialOffer = "special-offer"
    case tokens
    case other
}

public enum BroadLogRemoteConfigurationProvenance: String, Equatable, Sendable {
    case verifiedFreshRemote = "verified-fresh-remote"
    case providerCacheFallbackPossible = "provider-cache-fallback-possible"
    case platformCache = "platform-cache"
    case legacyUnqualified = "legacy-unqualified"
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
    case remoteFeatureFixtureEvaluated(
        scenario: String,
        state: String,
        requestedPlacement: String?,
        resolvedPlacement: String?,
        variation: String?,
        provenance: String?
    )
    case remoteFeatureFixtureResolved(
        scenario: BroadLogRemoteFeatureFixtureScenario,
        resolution: BroadLogRemoteFeatureResolution,
        requestedPlacement: BroadLogPlacement?,
        resolvedPlacement: BroadLogPlacement?,
        hasVariation: Bool,
        provenance: BroadLogRemoteConfigurationProvenance?
    )
    case projectInputsRead(kaiten: Bool, design: Bool, reference: Bool, backend: Bool)
    case backendMappingProgress(mapped: Int, total: Int)
    case flowAdvanced(source: BroadLogFlowStage, destination: BroadLogFlowStage)
    case tokenBalanceConfirmed
    case analyticsEventsRecorded(count: Int)
    case uiVisualReviewRemaining(count: Int)
    case workBlocked(capability: BroadLogBackendCapability, reason: BroadLogBlocker)
    case verificationPassed(BroadLogVerificationScope)

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
        case .remoteFeatureFixtureEvaluated, .remoteFeatureFixtureResolved:
            .experiments
        case .projectInputsRead:
            .input
        case .backendMappingProgress:
            .backend
        case .flowAdvanced:
            .flow
        case .tokenBalanceConfirmed:
            .tokens
        case .analyticsEventsRecorded:
            .analytics
        case .uiVisualReviewRemaining:
            .userInterface
        case .workBlocked:
            .blocked
        case .verificationPassed:
            .pass
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
        case .remoteFeatureFixtureEvaluated, .remoteFeatureFixtureResolved:
            .info
        case .projectInputsRead,
             .backendMappingProgress,
             .flowAdvanced,
             .tokenBalanceConfirmed,
             .analyticsEventsRecorded,
             .verificationPassed:
            .info
        case .uiVisualReviewRemaining:
            .warning
        case .workBlocked:
            .error
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
        case .remoteFeatureFixtureEvaluated: "remote-feature.fixture.evaluated"
        case .remoteFeatureFixtureResolved: "remote-feature.fixture.resolved"
        case .projectInputsRead: "inputs.read"
        case .backendMappingProgress: "backend.mapping.progress"
        case .flowAdvanced: "flow.advanced"
        case .tokenBalanceConfirmed: "tokens.balance.confirmed"
        case .analyticsEventsRecorded: "analytics.events.recorded"
        case .uiVisualReviewRemaining: "ui.visual-review.remaining"
        case .workBlocked: "work.blocked"
        case .verificationPassed: "verification.passed"
        }
    }
}

extension BroadLogCategory {
    var displayTag: String {
        switch self {
        case .bootstrap: "BOOTSTRAP"
        case .cache: "CACHE"
        case .networking: "NETWORKING"
        case .monetization: "MONETIZATION"
        case .paywall: "PAYWALL"
        case .purchase: "PURCHASE"
        case .ruBilling: "RU_BILLING"
        case .experiments: "EXPERIMENTS"
        case .input: "INPUT"
        case .backend: "BACKEND"
        case .flow: "FLOW"
        case .tokens: "TOKENS"
        case .analytics: "ANALYTICS"
        case .userInterface: "UI"
        case .blocked: "BLOCKED"
        case .pass: "PASS"
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
