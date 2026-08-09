public struct RequestTrackingAuthorizationUseCase: TrackingAuthorizationUseCaseProtocol {
    private let repository: any TrackingAuthorizationRepositoryProtocol

    public init(repository: any TrackingAuthorizationRepositoryProtocol) {
        self.repository = repository
    }

    @MainActor
    @discardableResult
    public func callAsFunction() async -> TrackingAuthorizationStatus {
        let status = repository.authorizationStatus()

        guard status.canRequestAuthorization, !Task.isCancelled else {
            return status
        }

        return await repository.requestAuthorization()
    }
}
