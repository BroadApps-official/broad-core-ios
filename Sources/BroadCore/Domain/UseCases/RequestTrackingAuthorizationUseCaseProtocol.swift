public protocol TrackingAuthorizationUseCaseProtocol: Sendable {
    @MainActor
    @discardableResult
    func callAsFunction() async -> TrackingAuthorizationStatus
}
