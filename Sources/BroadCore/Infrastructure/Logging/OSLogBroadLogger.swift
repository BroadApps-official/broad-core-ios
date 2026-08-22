import OSLog

public struct OSLogBroadLogger: BroadLoggerProtocol {
    private let bootstrapLogger: Logger
    private let cacheLogger: Logger
    private let networkingLogger: Logger
    private let monetizationLogger: Logger
    private let paywallLogger: Logger
    private let purchaseLogger: Logger
    private let ruBillingLogger: Logger
    private let experimentsLogger: Logger

    public init(subsystem: StaticString) {
        let subsystemValue = subsystem.description
        precondition(!subsystemValue.isEmpty, "Logging subsystem must not be empty")
        precondition(subsystemValue.utf8.count <= 255, "Logging subsystem must not exceed 255 UTF-8 bytes")
        bootstrapLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.bootstrap.rawValue)
        cacheLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.cache.rawValue)
        networkingLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.networking.rawValue)
        monetizationLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.monetization.rawValue)
        paywallLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.paywall.rawValue)
        purchaseLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.purchase.rawValue)
        ruBillingLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.ruBilling.rawValue)
        experimentsLogger = Logger(subsystem: subsystemValue, category: BroadLogCategory.experiments.rawValue)
    }

    public func log(_ event: BroadLogEvent) {
        let logger = logger(for: event.category)
        let message = message(for: event)

        switch event.level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }

    private func logger(for category: BroadLogCategory) -> Logger {
        switch category {
        case .bootstrap:
            bootstrapLogger
        case .cache:
            cacheLogger
        case .networking:
            networkingLogger
        case .monetization:
            monetizationLogger
        case .paywall:
            paywallLogger
        case .purchase:
            purchaseLogger
        case .ruBilling:
            ruBillingLogger
        case .experiments:
            experimentsLogger
        }
    }

    private func message(for event: BroadLogEvent) -> String {
        switch event {
        case .bootstrapStepStarted,
             .bootstrapStepRetried,
             .bootstrapStepCompleted,
             .bootstrapStepDegraded,
             .bootstrapStepFailed,
             .bootstrapStepTimedOut,
             .bootstrapStepCancelled:
            bootstrapStepMessage(for: event)
        case .cacheReadCompleted, .cacheOperationCompleted, .cacheOperationFailed:
            cacheMessage(for: event)
        case .remoteFeatureFixtureEvaluated:
            remoteFeatureFixtureMessage(for: event)
        default:
            bootstrapLifecycleMessage(for: event)
        }
    }

    private func bootstrapLifecycleMessage(for event: BroadLogEvent) -> String {
        switch event {
        case let .bootstrapRunStarted(criticalStepCount, backgroundStepCount):
            "\(event.name) critical_steps=\(criticalStepCount) background_steps=\(backgroundStepCount)"
        case .bootstrapRunJoined, .bootstrapRetryRequested, .bootstrapRunCancelled:
            event.name
        case let .bootstrapStateChanged(state):
            "\(event.name) state=\(state.rawValue)"
        case let .bootstrapBackgroundStarted(stepCount):
            "\(event.name) step_count=\(stepCount)"
        case let .bootstrapBackgroundFinished(outcome):
            "\(event.name) outcome=\(outcome.rawValue)"
        default:
            event.name
        }
    }

    private func bootstrapStepMessage(for event: BroadLogEvent) -> String {
        switch event {
        case let .bootstrapStepStarted(index, kind):
            stepMessage(event, index: index, kind: kind)
        case let .bootstrapStepRetried(index, kind, retryCount):
            "\(stepMessage(event, index: index, kind: kind)) retry_count=\(retryCount)"
        case let .bootstrapStepCompleted(index, kind, attemptCount):
            "\(stepMessage(event, index: index, kind: kind)) attempt_count=\(attemptCount)"
        case let .bootstrapStepDegraded(index, kind, attemptCount, errorKind):
            stepFailureMessage(
                event,
                index: index,
                kind: kind,
                attemptCount: attemptCount,
                errorKind: errorKind
            )
        case let .bootstrapStepFailed(index, kind, attemptCount, errorKind):
            stepFailureMessage(
                event,
                index: index,
                kind: kind,
                attemptCount: attemptCount,
                errorKind: errorKind
            )
        case let .bootstrapStepTimedOut(index, kind), let .bootstrapStepCancelled(index, kind):
            stepMessage(event, index: index, kind: kind)
        default:
            event.name
        }
    }

    private func cacheMessage(for event: BroadLogEvent) -> String {
        switch event {
        case let .cacheReadCompleted(result):
            "\(event.name) result=\(result.rawValue)"
        case let .cacheOperationCompleted(operation):
            "\(event.name) operation=\(operation.rawValue)"
        case let .cacheOperationFailed(operation, failure):
            "\(event.name) operation=\(operation.rawValue) failure=\(failure.rawValue)"
        default:
            event.name
        }
    }

    private func remoteFeatureFixtureMessage(for event: BroadLogEvent) -> String {
        guard case let .remoteFeatureFixtureEvaluated(
            scenario,
            state,
            requestedPlacement,
            resolvedPlacement,
            variation,
            provenance
        ) = event else {
            return event.name
        }
        return "\(event.name) scenario=\(scenario) state=\(state) "
            + "requested=\(requestedPlacement ?? "nil") "
            + "resolved=\(resolvedPlacement ?? "nil") "
            + "variation=\(variation ?? "nil") "
            + "provenance=\(provenance ?? "nil")"
    }

    private func stepMessage(
        _ event: BroadLogEvent,
        index: Int,
        kind: BroadLogBootstrapStepKind
    ) -> String {
        "\(event.name) index=\(index) kind=\(kind.rawValue)"
    }

    private func stepFailureMessage(
        _ event: BroadLogEvent,
        index: Int,
        kind: BroadLogBootstrapStepKind,
        attemptCount: Int,
        errorKind: AppError.Kind
    ) -> String {
        "\(stepMessage(event, index: index, kind: kind)) attempt_count=\(attemptCount) error_kind=\(errorKind.rawValue)"
    }
}
