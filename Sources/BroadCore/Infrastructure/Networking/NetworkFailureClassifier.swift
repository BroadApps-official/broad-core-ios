import Foundation

/// Safe transport classification. It intentionally drops raw URL/error text so
/// callers can drive retry UI without leaking request details.
public enum NetworkFailureKind: Equatable, Sendable {
    case offline
    case timedOut
    case cancelled
    case other
}

public enum NetworkFailureClassifier {
    public static func classify(_ error: any Error) -> NetworkFailureKind {
        if error is CancellationError {
            return .cancelled
        }
        guard let urlError = error as? URLError else {
            return .other
        }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed,
             .backgroundSessionWasDisconnected:
            return .offline
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        default:
            return .other
        }
    }
}
