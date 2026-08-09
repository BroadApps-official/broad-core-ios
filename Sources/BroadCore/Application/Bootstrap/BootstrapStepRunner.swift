enum BootstrapCriticalRunResult: Sendable {
    case completed(isDegraded: Bool)
    case failed(AppError)
    case cancelled
}

private enum BootstrapAttemptResult: Sendable {
    case completed(BootstrapStepCompletion, attemptCount: Int)
    case failed(AppError, attemptCount: Int)
    case timedOut(AppError)
    case cancelled
}

enum BootstrapStepRunner {
    static func executeCriticalSteps(
        _ steps: [BootstrapStep],
        errorMessages: BootstrapErrorMessages,
        logger: any BroadLoggerProtocol
    ) async -> BootstrapCriticalRunResult {
        var isDegraded = false

        for (index, step) in steps.enumerated() {
            switch await executeWithinBudget(
                step,
                index: index,
                errorMessages: errorMessages,
                logger: logger
            ) {
            case .completed(.completed, _):
                continue
            case .completed(.degraded, _):
                isDegraded = true
            case let .failed(error, _), let .timedOut(error):
                return .failed(error)
            case .cancelled:
                return .cancelled
            }
        }

        return .completed(isDegraded: isDegraded)
    }

    static func executeBackgroundSteps(
        _ steps: [BootstrapStep],
        errorMessages: BootstrapErrorMessages,
        logger: any BroadLoggerProtocol
    ) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for (index, step) in steps.enumerated() {
                group.addTask {
                    switch await executeWithinBudget(
                        step,
                        index: index,
                        errorMessages: errorMessages,
                        logger: logger
                    ) {
                    case .completed(.completed, _):
                        false
                    case .completed(.degraded, _), .failed, .timedOut:
                        true
                    case .cancelled:
                        false
                    }
                }
            }

            var isDegraded = false
            for await stepIsDegraded in group {
                isDegraded = isDegraded || stepIsDegraded
            }
            return isDegraded
        }
    }

    private static func executeWithinBudget(
        _ step: BootstrapStep,
        index: Int,
        errorMessages: BootstrapErrorMessages,
        logger: any BroadLoggerProtocol
    ) async -> BootstrapAttemptResult {
        logger.log(
            .bootstrapStepStarted(
                index: index,
                kind: logKind(for: step.criticality)
            )
        )
        let race = BootstrapAttemptRace()
        let operationTask = Task {
            let result = await executeWithRetry(
                step,
                errorMessages: errorMessages
            )
            await race.resolve(result)
        }
        let timeoutTask = Task {
            do {
                try await ContinuousClock().sleep(for: step.timeoutPolicy.limit)
                await race.resolve(
                    .timedOut(
                        .bootstrapTimeout(
                            stepID: step.id,
                            userMessage: errorMessages.timeout
                        )
                    )
                )
            } catch {
                // The operation won the race or the whole bootstrap run was cancelled.
            }
        }

        let result = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.resolve(.cancelled)
            }
        }

        operationTask.cancel()
        timeoutTask.cancel()
        log(
            result,
            step: step,
            index: index,
            logger: logger
        )
        return result
    }

    private static func executeWithRetry(
        _ step: BootstrapStep,
        errorMessages: BootstrapErrorMessages
    ) async -> BootstrapAttemptResult {
        let clock = ContinuousClock()
        var retryIndex = 0
        var attemptCount = 1

        while true {
            do {
                try Task.checkCancellation()
                let completion = try await step.execute()
                try Task.checkCancellation()
                return .completed(completion, attemptCount: attemptCount)
            } catch is CancellationError {
                return .cancelled
            } catch {
                let appError = AppError.sanitized(
                    from: error,
                    userMessage: errorMessages.unknown
                )
                guard appError.isRetryable, retryIndex < step.retryPolicy.delays.count else {
                    return .failed(appError, attemptCount: attemptCount)
                }

                let delay = step.retryPolicy.delays[retryIndex]
                retryIndex += 1

                do {
                    try await clock.sleep(for: delay)
                    attemptCount += 1
                } catch {
                    return .cancelled
                }
            }
        }
    }

    private static func log(
        _ result: BootstrapAttemptResult,
        step: BootstrapStep,
        index: Int,
        logger: any BroadLoggerProtocol
    ) {
        let kind = logKind(for: step.criticality)

        switch result {
        case let .completed(.completed, attemptCount):
            logRetries(attemptCount, index: index, kind: kind, logger: logger)
            logger.log(.bootstrapStepCompleted(index: index, kind: kind, attemptCount: attemptCount))
        case let .completed(.degraded(error), attemptCount):
            logRetries(attemptCount, index: index, kind: kind, logger: logger)
            logger.log(
                .bootstrapStepDegraded(
                    index: index,
                    kind: kind,
                    attemptCount: attemptCount,
                    errorKind: error.kind
                )
            )
        case let .failed(error, attemptCount):
            logRetries(attemptCount, index: index, kind: kind, logger: logger)
            logger.log(
                .bootstrapStepFailed(
                    index: index,
                    kind: kind,
                    attemptCount: attemptCount,
                    errorKind: error.kind
                )
            )
        case .timedOut:
            logger.log(.bootstrapStepTimedOut(index: index, kind: kind))
        case .cancelled:
            logger.log(.bootstrapStepCancelled(index: index, kind: kind))
        }
    }

    private static func logRetries(
        _ attemptCount: Int,
        index: Int,
        kind: BroadLogBootstrapStepKind,
        logger: any BroadLoggerProtocol
    ) {
        let retryCount = attemptCount - 1
        guard retryCount > 0 else {
            return
        }

        logger.log(
            .bootstrapStepRetried(
                index: index,
                kind: kind,
                retryCount: retryCount
            )
        )
    }

    private static func logKind(
        for criticality: BootstrapCriticality
    ) -> BroadLogBootstrapStepKind {
        switch criticality {
        case .critical:
            .critical
        case .background:
            .background
        }
    }
}

private extension AppError {
    static func sanitized(
        from error: any Error,
        userMessage: String
    ) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        return AppError(
            kind: .unknown,
            userMessage: userMessage,
            diagnosticCode: "bootstrap.unknown",
            isRetryable: false
        )
    }

    static func bootstrapTimeout(
        stepID: BootstrapStepID,
        userMessage: String
    ) -> AppError {
        AppError(
            kind: .timeout,
            userMessage: userMessage,
            diagnosticCode: "bootstrap.timeout.\(stepID.rawValue)",
            isRetryable: true
        )
    }
}

private actor BootstrapAttemptRace {
    private var result: BootstrapAttemptResult?
    private var continuation: CheckedContinuation<BootstrapAttemptResult, Never>?

    func value() async -> BootstrapAttemptResult {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ result: BootstrapAttemptResult) {
        guard self.result == nil else {
            return
        }

        self.result = result
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
