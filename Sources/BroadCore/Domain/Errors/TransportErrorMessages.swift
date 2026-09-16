import Foundation

/// The four sentences a host shows for a request that never produced an answer.
///
/// Every application writes these four again, and each copy drifts: one forgets
/// that a lost DNS lookup is the same story as no connection, another marks a
/// timeout as final. The strings stay the host's — they are user-facing product
/// copy — but the classification and the retry decision do not.
public struct TransportErrorMessages: Equatable, Sendable {
    public static let englishDefault = TransportErrorMessages(
        offline: "No internet connection. Check the network and try again.",
        timedOut: "The request took too long. Please try again.",
        cancelled: "The request was cancelled.",
        other: "Something went wrong. Please try again."
    )

    public let offline: String
    public let timedOut: String
    public let cancelled: String
    public let other: String

    public init(
        offline: String,
        timedOut: String,
        cancelled: String,
        other: String
    ) {
        precondition(!offline.isEmpty, "Offline message must not be empty")
        precondition(!timedOut.isEmpty, "Timeout message must not be empty")
        precondition(!cancelled.isEmpty, "Cancellation message must not be empty")
        precondition(!other.isEmpty, "Unknown transport message must not be empty")

        self.offline = offline
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.other = other
    }

    /// The sentence for one classified failure.
    public func message(for kind: NetworkFailureKind) -> String {
        switch kind {
        case .offline: offline
        case .timedOut: timedOut
        case .cancelled: cancelled
        case .other: other
        }
    }
}

public extension NetworkFailureKind {
    /// The ``AppError`` kind this transport failure belongs to.
    var appErrorKind: AppError.Kind {
        switch self {
        case .offline: .offline
        case .timedOut: .timeout
        case .cancelled: .unknown
        case .other: .unknown
        }
    }

    /// Whether the same request is worth sending again.
    ///
    /// A cancelled request is not retried on its own: the caller walked away,
    /// and it is the caller who decides whether to ask again.
    var isRetryable: Bool {
        switch self {
        case .offline, .timedOut, .other: true
        case .cancelled: false
        }
    }

    /// Stable suffix for a diagnostic code, so one failure reads the same in
    /// every application's log.
    var diagnosticSuffix: String {
        switch self {
        case .offline: "offline"
        case .timedOut: "timeout"
        case .cancelled: "cancelled"
        case .other: "transport"
        }
    }
}

public extension AppError {
    /// Turns a transport failure into an ``AppError``, keeping the host's copy
    /// and the platform's classification.
    ///
    /// `diagnosticPrefix` names the caller — `"app.backend"`, say — and the
    /// failure appends its own suffix, so the code reads `app.backend.offline`.
    /// Raw URL and error text is never carried into the result.
    ///
    /// - Parameters:
    ///   - error: the error a request threw.
    ///   - messages: the host's user-facing copy.
    ///   - diagnosticPrefix: what to put in front of the failure's own suffix.
    static func transportFailure(
        _ error: any Error,
        messages: TransportErrorMessages = .englishDefault,
        diagnosticPrefix: String
    ) -> AppError {
        transportFailure(
            NetworkFailureClassifier.classify(error),
            messages: messages,
            diagnosticPrefix: diagnosticPrefix
        )
    }

    /// Turns an already classified transport failure into an ``AppError``.
    static func transportFailure(
        _ kind: NetworkFailureKind,
        messages: TransportErrorMessages = .englishDefault,
        diagnosticPrefix: String
    ) -> AppError {
        precondition(
            !diagnosticPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Diagnostic prefix must not be empty"
        )

        return AppError(
            kind: kind.appErrorKind,
            userMessage: messages.message(for: kind),
            diagnosticCode: "\(diagnosticPrefix).\(kind.diagnosticSuffix)",
            isRetryable: kind.isRetryable
        )
    }
}
