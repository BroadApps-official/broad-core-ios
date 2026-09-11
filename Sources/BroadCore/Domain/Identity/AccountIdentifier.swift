/// Where the account identifier of this launch came from.
///
/// It tells a new phone apart from a fresh install: an identifier that arrived
/// through iCloud Keychain belongs to an account that already exists on another
/// device, with its purchases and server data. What to do with that is the host's
/// decision, for example whether to restore server history.
public enum AccountIdentifierSource: String, Equatable, Sendable {
    /// Supplied by the host from its own storage: an install that predates the store.
    case legacy

    /// This device's own Keychain item, written on an earlier launch or before a reinstall.
    case device

    /// Written by another device on the same Apple ID and synced through iCloud Keychain.
    case iCloudKeychain

    /// Nothing was stored anywhere, so a new identifier was created and stored.
    case generated
}

public enum AccountIdentifierResolution: Equatable, Sendable {
    case resolved(identifier: String, source: AccountIdentifierSource)

    /// Keychain could not be read, or a new identifier could not be stored. The
    /// caller retries later instead of starting another account.
    case failed(AppError)

    public var identifier: String? {
        switch self {
        case let .resolved(identifier, _):
            identifier
        case .failed:
            nil
        }
    }
}

/// A stable identifier of the user's account in this app, such as the customer
/// user ID a host passes to its purchase provider and backend.
public protocol AccountIdentifierProviderProtocol: Sendable {
    func resolve() async -> AccountIdentifierResolution
}
