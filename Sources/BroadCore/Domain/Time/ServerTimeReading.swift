import Foundation

/// What the platform can prove about the current time.
///
/// Every reading carries a usable date, so a caller is never left without one.
/// The case says how much that date is worth: `.synchronized` was derived from an
/// answer of the host's own backend, `.unverified` is the device clock, which the
/// user can move. Anything that decides money or a deadline must branch on this
/// rather than take the date alone.
public enum ServerTimeReading: Equatable, Sendable {
    /// Derived from a recorded server date. The offset to the device clock is
    /// applied and the value never moves backwards.
    case synchronized(Date)

    /// No server date has been recorded yet, so this is the device clock.
    case unverified(Date)

    public var date: Date {
        switch self {
        case let .synchronized(date), let .unverified(date):
            date
        }
    }

    public var isSynchronized: Bool {
        switch self {
        case .synchronized:
            true
        case .unverified:
            false
        }
    }
}

/// A source of the current time that states how trustworthy it is.
///
/// Kept separate from the concrete clock so a feature can depend on the contract,
/// and so a host that already owns trusted time can supply its own conformance.
public protocol ServerTimeProviderProtocol: Sendable {
    func reading() async -> ServerTimeReading
}
