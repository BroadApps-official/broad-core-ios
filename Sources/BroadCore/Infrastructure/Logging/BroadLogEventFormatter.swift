/// Единственное место, где typed-событие превращается в безопасную строку
/// `[TAG] event.name key=value`. Все поля берутся только из закрытых enum, Bool
/// и счётчиков, поэтому строка не может содержать payload, секрет или PII.
/// `OSLogBroadLogger` и `BroadSupportLogRecorder` используют один и тот же
/// форматтер, чтобы Console и вложение к письму в поддержку совпадали дословно.
enum BroadLogEventFormatter {
    static func line(for event: BroadLogEvent) -> String {
        "[\(event.category.displayTag)] \(message(for: event))"
    }

    static func message(for event: BroadLogEvent) -> String {
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

    private static func developmentStatusMessage(for event: BroadLogEvent) -> String {
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

    private static func bootstrapLifecycleMessage(for event: BroadLogEvent) -> String {
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

    private static func bootstrapStepMessage(for event: BroadLogEvent) -> String {
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

    private static func cacheMessage(for event: BroadLogEvent) -> String {
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

    private static func remoteFeatureFixtureMessage(for event: BroadLogEvent) -> String {
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

    private static func stepMessage(
        _ event: BroadLogEvent,
        index: Int,
        kind: BroadLogBootstrapStepKind
    ) -> String {
        "\(event.name) index=\(index) kind=\(kind.rawValue)"
    }

    private static func stepFailureMessage(
        _ event: BroadLogEvent,
        index: Int,
        kind: BroadLogBootstrapStepKind,
        attemptCount: Int,
        errorKind: AppError.Kind
    ) -> String {
        "\(stepMessage(event, index: index, kind: kind)) attempt_count=\(attemptCount) error_kind=\(errorKind.rawValue)"
    }
}
