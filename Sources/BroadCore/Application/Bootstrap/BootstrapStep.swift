import Foundation

public struct BootstrapStepID: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "Bootstrap step ID must not be empty")
        self.rawValue = rawValue
    }
}

public enum BootstrapCriticality: Equatable, Sendable {
    case critical
    case background
}

public enum BootstrapStepCompletion: Equatable, Sendable {
    case completed
    case degraded(AppError)
}

public struct BootstrapStep: Sendable {
    public typealias Operation = @Sendable () async throws -> BootstrapStepCompletion

    public let id: BootstrapStepID
    public let name: String
    public let criticality: BootstrapCriticality
    public let timeoutPolicy: TimeoutPolicy
    public let retryPolicy: RetryPolicy

    private let executionGate: BootstrapStepExecutionGate

    public init(
        id: BootstrapStepID,
        name: String,
        criticality: BootstrapCriticality,
        timeoutPolicy: TimeoutPolicy,
        retryPolicy: RetryPolicy,
        operation: @escaping Operation
    ) {
        precondition(!name.isEmpty, "Bootstrap step name must not be empty")

        self.id = id
        self.name = name
        self.criticality = criticality
        self.timeoutPolicy = timeoutPolicy
        self.retryPolicy = retryPolicy
        executionGate = BootstrapStepExecutionGate(operation: operation)
    }

    func execute() async throws -> BootstrapStepCompletion {
        try await executionGate.execute()
    }
}

private actor BootstrapStepExecutionGate {
    private struct ActiveExecution {
        let id: UUID
        let task: Task<BootstrapStepCompletion, any Error>
    }

    private let operation: BootstrapStep.Operation
    private var activeExecution: ActiveExecution?

    init(operation: @escaping BootstrapStep.Operation) {
        self.operation = operation
    }

    func execute() async throws -> BootstrapStepCompletion {
        if let activeExecution {
            return try await value(of: activeExecution)
        }

        let execution = ActiveExecution(
            id: UUID(),
            task: Task {
                try await operation()
            }
        )
        activeExecution = execution
        return try await value(of: execution)
    }

    private func value(of execution: ActiveExecution) async throws -> BootstrapStepCompletion {
        do {
            let value = try await execution.task.value
            clear(execution)
            return value
        } catch {
            clear(execution)
            throw error
        }
    }

    private func clear(_ execution: ActiveExecution) {
        guard activeExecution?.id == execution.id else {
            return
        }

        activeExecution = nil
    }
}
