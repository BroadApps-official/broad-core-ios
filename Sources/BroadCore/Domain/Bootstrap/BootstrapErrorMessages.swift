public struct BootstrapErrorMessages: Equatable, Sendable {
    public static let englishDefault = BootstrapErrorMessages(
        timeout: "Startup took too long. Please try again.",
        unknown: "Something went wrong. Please try again."
    )

    public let timeout: String
    public let unknown: String

    public init(timeout: String, unknown: String) {
        precondition(!timeout.isEmpty, "Bootstrap timeout message must not be empty")
        precondition(!unknown.isEmpty, "Bootstrap unknown-error message must not be empty")

        self.timeout = timeout
        self.unknown = unknown
    }
}
