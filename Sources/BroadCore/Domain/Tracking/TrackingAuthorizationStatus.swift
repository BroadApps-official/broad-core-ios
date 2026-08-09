public enum TrackingAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case unknown

    public var canRequestAuthorization: Bool {
        self == .notDetermined
    }
}
