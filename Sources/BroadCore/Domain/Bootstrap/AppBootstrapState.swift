public enum AppBootstrapState: Equatable, Sendable {
    case idle
    case starting
    case ready
    case degraded
    case failed(AppError)
}
