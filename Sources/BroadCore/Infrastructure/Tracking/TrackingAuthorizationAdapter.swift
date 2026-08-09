import AppTrackingTransparency

public struct SystemTrackingAuthorizationAdapter: TrackingAuthorizationRepositoryProtocol {
    public init() {}

    @MainActor
    public func authorizationStatus() -> TrackingAuthorizationStatus {
        Self.map(ATTrackingManager.trackingAuthorizationStatus)
    }

    @MainActor
    public func requestAuthorization() async -> TrackingAuthorizationStatus {
        let currentStatus = authorizationStatus()

        guard currentStatus.canRequestAuthorization, !Task.isCancelled else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    private static func map(
        _ status: ATTrackingManager.AuthorizationStatus
    ) -> TrackingAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}
