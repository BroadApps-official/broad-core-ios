public protocol RunAppBootstrapUseCaseProtocol: Sendable {
    var state: AppBootstrapState { get async }

    func states() async -> AsyncStream<AppBootstrapState>

    @discardableResult
    func callAsFunction() async -> AppBootstrapState

    @discardableResult
    func retry() async -> AppBootstrapState

    func cancel() async
}
