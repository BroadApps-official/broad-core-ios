public struct AppError: Error, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case offline
        case timeout
        case unauthorized
        case server
        case decoding
        case unavailable
        case unknown
    }

    public let kind: Kind
    public let userMessage: String
    public let diagnosticCode: String
    public let isRetryable: Bool

    public init(
        kind: Kind,
        userMessage: String,
        diagnosticCode: String,
        isRetryable: Bool
    ) {
        precondition(!userMessage.isEmpty, "AppError userMessage must not be empty")
        precondition(!diagnosticCode.isEmpty, "AppError diagnosticCode must not be empty")

        self.kind = kind
        self.userMessage = userMessage
        self.diagnosticCode = diagnosticCode
        self.isRetryable = isRetryable
    }
}
