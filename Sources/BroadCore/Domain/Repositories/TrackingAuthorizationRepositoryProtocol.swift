public protocol TrackingAuthorizationRepositoryProtocol: Sendable {
    @MainActor
    func authorizationStatus() -> TrackingAuthorizationStatus

    @MainActor
    func requestAuthorization() async -> TrackingAuthorizationStatus
}
