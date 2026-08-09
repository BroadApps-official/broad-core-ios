import Foundation

public actor AppBootstrapCoordinator: RunAppBootstrapUseCaseProtocol {
    private let steps: [BootstrapStep]
    private let errorMessages: BootstrapErrorMessages
    private let logger: any BroadLoggerProtocol

    private var currentState: AppBootstrapState = .idle
    private var continuations: [UUID: AsyncStream<AppBootstrapState>.Continuation] = [:]
    private var generation: UInt64 = 0
    private var activeRunGeneration: UInt64?
    private var activeRunTask: Task<BootstrapCriticalRunResult, Never>?
    private var completedRunGeneration: UInt64?
    private var completedRunState: AppBootstrapState?
    private var backgroundGeneration: UInt64?
    private var backgroundTask: Task<Void, Never>?

    public var state: AppBootstrapState {
        currentState
    }

    public init(
        steps: [BootstrapStep],
        errorMessages: BootstrapErrorMessages = .englishDefault,
        logger: any BroadLoggerProtocol = NoOpBroadLogger()
    ) {
        let identifiers = steps.map(\.id)
        precondition(Set(identifiers).count == identifiers.count, "Bootstrap step IDs must be unique")
        self.steps = steps
        self.errorMessages = errorMessages
        self.logger = logger
    }

    public func states() async -> AsyncStream<AppBootstrapState> {
        let observerID = UUID()
        let pair = AsyncStream.makeStream(
            of: AppBootstrapState.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        pair.continuation.yield(currentState)
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeContinuation(observerID)
            }
        }
        continuations[observerID] = pair.continuation

        return pair.stream
    }

    @discardableResult
    public func callAsFunction() async -> AppBootstrapState {
        if let activeRunTask, let activeRunGeneration {
            logger.log(.bootstrapRunJoined)
            let result = await activeRunTask.value
            return completeCriticalRun(result, generation: activeRunGeneration)
        }

        guard currentState == .idle else {
            return currentState
        }

        return await startNewRun()
    }

    @discardableResult
    public func retry() async -> AppBootstrapState {
        if let activeRunTask, let activeRunGeneration {
            logger.log(.bootstrapRunJoined)
            let result = await activeRunTask.value
            return completeCriticalRun(result, generation: activeRunGeneration)
        }

        guard case .failed = currentState else {
            return currentState
        }

        logger.log(.bootstrapRetryRequested)
        cancelTrackedWork()
        return await startNewRun()
    }

    public func cancel() async {
        if activeRunTask != nil || backgroundTask != nil {
            logger.log(.bootstrapRunCancelled)
        }

        cancelTrackedWork()
        transition(to: .idle)
    }

    private func startNewRun() async -> AppBootstrapState {
        generation &+= 1
        let runGeneration = generation
        let criticalSteps = steps.filter { $0.criticality == .critical }
        let backgroundStepCount = steps.lazy.filter { $0.criticality == .background }.count
        let errorMessages = errorMessages
        let logger = logger

        logger.log(
            .bootstrapRunStarted(
                criticalStepCount: criticalSteps.count,
                backgroundStepCount: backgroundStepCount
            )
        )
        transition(to: .starting)

        let task = Task {
            await BootstrapStepRunner.executeCriticalSteps(
                criticalSteps,
                errorMessages: errorMessages,
                logger: logger
            )
        }
        activeRunGeneration = runGeneration
        activeRunTask = task

        let result = await task.value
        return completeCriticalRun(result, generation: runGeneration)
    }

    private func completeCriticalRun(
        _ result: BootstrapCriticalRunResult,
        generation runGeneration: UInt64
    ) -> AppBootstrapState {
        guard activeRunGeneration == runGeneration else {
            if completedRunGeneration == runGeneration, let completedRunState {
                return completedRunState
            }

            return .idle
        }

        activeRunGeneration = nil
        activeRunTask = nil

        switch result {
        case let .completed(isDegraded):
            transition(to: isDegraded ? .degraded : .ready)
            startBackgroundSteps(generation: runGeneration)
        case let .failed(error):
            transition(to: .failed(error))
        case .cancelled:
            transition(to: .idle)
        }

        completedRunGeneration = runGeneration
        completedRunState = currentState
        return currentState
    }

    private func startBackgroundSteps(generation runGeneration: UInt64) {
        let backgroundSteps = steps.filter { $0.criticality == .background }
        let errorMessages = errorMessages
        let logger = logger
        guard !backgroundSteps.isEmpty else {
            return
        }

        logger.log(.bootstrapBackgroundStarted(stepCount: backgroundSteps.count))
        backgroundGeneration = runGeneration
        let task = Task { [weak self] in
            let isDegraded = await BootstrapStepRunner.executeBackgroundSteps(
                backgroundSteps,
                errorMessages: errorMessages,
                logger: logger
            )
            await self?.completeBackgroundRun(
                isDegraded: isDegraded,
                generation: runGeneration
            )
        }
        backgroundTask = task
    }

    private func completeBackgroundRun(
        isDegraded: Bool,
        generation runGeneration: UInt64
    ) {
        guard backgroundGeneration == runGeneration else {
            return
        }

        backgroundGeneration = nil
        backgroundTask = nil
        logger.log(
            .bootstrapBackgroundFinished(
                isDegraded ? .degraded : .completed
            )
        )

        if isDegraded {
            transition(to: .degraded)
        }
    }

    private func cancelTrackedWork() {
        generation &+= 1
        activeRunTask?.cancel()
        backgroundTask?.cancel()
        activeRunTask = nil
        activeRunGeneration = nil
        backgroundTask = nil
        backgroundGeneration = nil
    }

    private func transition(to newState: AppBootstrapState) {
        guard currentState != newState else {
            return
        }

        currentState = newState
        logger.log(.bootstrapStateChanged(logState(for: newState)))
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }

    private func removeContinuation(_ observerID: UUID) {
        continuations[observerID] = nil
    }

    private func logState(for state: AppBootstrapState) -> BroadLogBootstrapState {
        switch state {
        case .idle:
            .idle
        case .starting:
            .starting
        case .ready:
            .ready
        case .degraded:
            .degraded
        case .failed:
            .failed
        }
    }
}
