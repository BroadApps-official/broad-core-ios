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
    private let inputLogger: Logger
    private let backendLogger: Logger
    private let flowLogger: Logger
    private let tokensLogger: Logger
    private let analyticsLogger: Logger
    private let uiLogger: Logger
    private let blockedLogger: Logger
    private let passLogger: Logger

    public init(subsystem: StaticString) {
        self.init(subsystem: subsystem.description)
    }

    /// Creates the logger from a runtime value such as
    /// `Bundle.main.bundleIdentifier`.
    public init(subsystem: String) {
        precondition(!subsystem.isEmpty, "Logging subsystem must not be empty")
        precondition(subsystem.utf8.count <= 255, "Logging subsystem must not exceed 255 UTF-8 bytes")
        bootstrapLogger = Logger(subsystem: subsystem, category: BroadLogCategory.bootstrap.rawValue)
        cacheLogger = Logger(subsystem: subsystem, category: BroadLogCategory.cache.rawValue)
        networkingLogger = Logger(subsystem: subsystem, category: BroadLogCategory.networking.rawValue)
        monetizationLogger = Logger(subsystem: subsystem, category: BroadLogCategory.monetization.rawValue)
        paywallLogger = Logger(subsystem: subsystem, category: BroadLogCategory.paywall.rawValue)
        purchaseLogger = Logger(subsystem: subsystem, category: BroadLogCategory.purchase.rawValue)
        ruBillingLogger = Logger(subsystem: subsystem, category: BroadLogCategory.ruBilling.rawValue)
        experimentsLogger = Logger(subsystem: subsystem, category: BroadLogCategory.experiments.rawValue)
        inputLogger = Logger(subsystem: subsystem, category: BroadLogCategory.input.rawValue)
        backendLogger = Logger(subsystem: subsystem, category: BroadLogCategory.backend.rawValue)
        flowLogger = Logger(subsystem: subsystem, category: BroadLogCategory.flow.rawValue)
        tokensLogger = Logger(subsystem: subsystem, category: BroadLogCategory.tokens.rawValue)
        analyticsLogger = Logger(subsystem: subsystem, category: BroadLogCategory.analytics.rawValue)
        uiLogger = Logger(
            subsystem: subsystem,
            category: BroadLogCategory.userInterface.rawValue
        )
        blockedLogger = Logger(subsystem: subsystem, category: BroadLogCategory.blocked.rawValue)
        passLogger = Logger(subsystem: subsystem, category: BroadLogCategory.pass.rawValue)
    }

    public func log(_ event: BroadLogEvent) {
        let logger = logger(for: event.category)
        let message = "[\(event.category.displayTag)] \(message(for: event))"

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
}

private extension OSLogBroadLogger {
    private func logger(for category: BroadLogCategory) -> Logger {
        switch category {
        case .input,
             .backend,
             .flow,
             .tokens,
             .analytics,
             .userInterface,
             .blocked,
             .pass:
            developmentLogger(for: category)
        default:
            platformLogger(for: category)
        }
    }

    private func platformLogger(for category: BroadLogCategory) -> Logger {
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
        default:
            developmentLogger(for: category)
        }
    }

    private func developmentLogger(for category: BroadLogCategory) -> Logger {
        switch category {
        case .input:
            inputLogger
        case .backend:
            backendLogger
        case .flow:
            flowLogger
        case .tokens:
            tokensLogger
        case .analytics:
            analyticsLogger
        case .userInterface:
            uiLogger
        case .blocked:
            blockedLogger
        case .pass:
            passLogger
        default:
            platformLogger(for: category)
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
        case .remoteFeatureFixtureEvaluated, .remoteFeatureFixtureResolved:
            remoteFeatureFixtureMessage(for: event)
        case let .ruBillingAvailabilityEvaluated(reason, methodCount):
            "\(event.name) reason=\(reason.rawValue) method_count=\(max(0, methodCount))"
        case .projectInputsRead,
             .backendMappingProgress,
             .flowAdvanced,
             .tokenBalanceConfirmed,
             .analyticsEventsRecorded,
             .uiVisualReviewRemaining,
             .workBlocked,
             .verificationPassed:
            developmentStatusMessage(for: event)
        default:
            bootstrapLifecycleMessage(for: event)
        }
    }

    private func developmentStatusMessage(for event: BroadLogEvent) -> String {
        switch event {
        case let .projectInputsRead(kaiten, design, reference, backend):
            "\(event.name) kaiten=\(kaiten) design=\(design) reference=\(reference) backend=\(backend)"
        case let .backendMappingProgress(mapped, total):
            "\(event.name) mapped=\(max(0, mapped)) total=\(max(0, total))"
        case let .flowAdvanced(source, destination):
            "\(event.name) from=\(source.rawValue) to=\(destination.rawValue)"
        case .tokenBalanceConfirmed:
            event.name
        case let .analyticsEventsRecorded(count):
            "\(event.name) count=\(max(0, count))"
        case let .uiVisualReviewRemaining(count):
            "\(event.name) count=\(max(0, count))"
        case let .workBlocked(capability, reason):
            "\(event.name) capability=\(capability.rawValue) reason=\(reason.rawValue)"
        case let .verificationPassed(scope):
            "\(event.name) scope=\(scope.rawValue)"
        default:
            event.name
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
        guard case let .remoteFeatureFixtureResolved(
            scenario,
            resolution,
            requestedPlacement,
            resolvedPlacement,
            hasVariation,
            provenance
        ) = event else {
            return "\(event.name) legacy_metadata=discarded"
        }
        return "\(event.name) scenario=\(scenario.rawValue) resolution=\(resolution.rawValue) "
            + "requested=\(requestedPlacement?.rawValue ?? "nil") "
            + "resolved=\(resolvedPlacement?.rawValue ?? "nil") "
            + "has_variation=\(hasVariation) "
            + "provenance=\(provenance?.rawValue ?? "nil")"
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
