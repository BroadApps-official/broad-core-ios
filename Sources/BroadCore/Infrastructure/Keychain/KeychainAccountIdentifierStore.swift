import Foundation
import Security

/// Where the account identifier is kept in Keychain. The names must stay the same
/// across app updates: a changed service or account no longer finds the stored item.
public struct KeychainAccountIdentifierConfiguration: Equatable, Sendable {
    public let service: String
    public let account: String
    /// A missing access group means the app's default Keychain access group.
    public let accessGroup: String?
    /// Also keep a copy in iCloud Keychain, so a new phone on the same Apple Account
    /// can resolve the same account. `false` never reads or writes the iCloud copy.
    public let synchronizesThroughICloudKeychain: Bool

    public init(
        service: String,
        account: String = "account-identifier",
        accessGroup: String? = nil,
        synchronizesThroughICloudKeychain: Bool = true
    ) {
        let normalizedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccessGroup = accessGroup?.trimmingCharacters(in: .whitespacesAndNewlines)

        precondition(!normalizedService.isEmpty, "Account identifier Keychain service must not be empty")
        precondition(!normalizedAccount.isEmpty, "Account identifier Keychain account must not be empty")
        precondition(
            normalizedAccessGroup?.isEmpty != true,
            "Account identifier Keychain access group must not be empty"
        )

        self.service = normalizedService
        self.account = normalizedAccount
        self.accessGroup = normalizedAccessGroup
        self.synchronizesThroughICloudKeychain = synchronizesThroughICloudKeychain
    }
}

/// Stable account identifier kept in Keychain and, when enabled, shared across the
/// user's devices through iCloud Keychain.
///
/// Order of resolution:
/// 1. The host's legacy identifier. An installed app already runs its purchases and
///    backend account under it, so on this device it stays the main one.
/// 2. This device's own item. It wins over iCloud Keychain, where another phone on
///    the same Apple Account may have put a different identifier.
/// 3. The item from iCloud Keychain: the device has none of its own.
/// 4. A new identifier.
///
/// Every resolved identifier is stored as this device's item first; otherwise the
/// result is `.failed` and the caller retries. A read that ends without a definite
/// answer also fails instead of starting another account. The iCloud copy is only
/// ever added, never replaced, so phones do not take the item over from each other.
/// The identifier is never logged.
public actor KeychainAccountIdentifierStore: AccountIdentifierProviderProtocol {
    private static let maximumIdentifierByteCount = 1024

    private let storage: any AccountIdentifierItemStorage
    private let synchronizes: Bool
    private let failureError: AppError
    private let legacyIdentifier: @Sendable () -> String?
    private let makeIdentifier: @Sendable () -> String
    private var resolution: AccountIdentifierResolution?

    public init(
        configuration: KeychainAccountIdentifierConfiguration,
        failureError: AppError,
        legacyIdentifier: @escaping @Sendable () -> String? = { nil }
    ) {
        self.init(
            storage: SecurityAccountIdentifierItemStorage(configuration: configuration),
            synchronizes: configuration.synchronizesThroughICloudKeychain,
            failureError: failureError,
            legacyIdentifier: legacyIdentifier,
            makeIdentifier: { UUID().uuidString }
        )
    }

    init(
        storage: any AccountIdentifierItemStorage,
        synchronizes: Bool,
        failureError: AppError,
        legacyIdentifier: @escaping @Sendable () -> String?,
        makeIdentifier: @escaping @Sendable () -> String
    ) {
        self.storage = storage
        self.synchronizes = synchronizes
        self.failureError = failureError
        self.legacyIdentifier = legacyIdentifier
        self.makeIdentifier = makeIdentifier
    }

    /// Resolves once per instance. Later calls return the same identifier and the
    /// source of the first resolution; a failure is not remembered and is retried.
    public func resolve() -> AccountIdentifierResolution {
        if let resolution {
            return resolution
        }
        let outcome = resolveFromStorage()
        if case .resolved = outcome {
            resolution = outcome
        }
        return outcome
    }
}

private extension KeychainAccountIdentifierStore {
    func resolveFromStorage() -> AccountIdentifierResolution {
        let deviceItem = storage.read(synchronizable: false)
        if deviceItem == .unavailable {
            // Keychain is locked or unavailable. A new identifier here would start a
            // second account for someone who already has one.
            return .failed(failureError)
        }
        let hasDeviceItem = deviceItem != .missing
        let own: String? = if case let .value(value) = deviceItem {
            Self.normalized(value)
        } else {
            nil
        }

        if let legacy = Self.normalized(legacyIdentifier()) {
            guard own == legacy || storeLegacyOnDevice(legacy, replacing: hasDeviceItem) else {
                // The migration is not finished; the host keeps its value and retries.
                return .failed(failureError)
            }
            addICloudCopy(legacy)
            return .resolved(identifier: legacy, source: .legacy)
        }

        if let own {
            addICloudCopy(own)
            return .resolved(identifier: own, source: .device)
        }

        if let joined = joinICloudCopy(replacing: hasDeviceItem) {
            return joined
        }

        guard let generated = Self.normalized(makeIdentifier()) else {
            return .failed(failureError)
        }
        let claimed = claimDeviceItem(generated, source: .generated, replacing: hasDeviceItem)
        guard claimed == .resolved(identifier: generated, source: .generated) else {
            return claimed
        }
        return shareGenerated(generated)
    }

    /// `nil` means there is no usable iCloud copy and a new identifier may be created.
    func joinICloudCopy(replacing hasDeviceItem: Bool) -> AccountIdentifierResolution? {
        guard synchronizes else { return nil }
        switch storage.read(synchronizable: true) {
        case let .value(value):
            guard let synced = Self.normalized(value) else { return nil }
            return claimDeviceItem(synced, source: .iCloudKeychain, replacing: hasDeviceItem)
        case .missing, .unreadable:
            return nil
        case .unavailable:
            // The iCloud copy may hold an existing account; do not decide without it.
            return .failed(failureError)
        }
    }

    /// The legacy identifier wins over whatever the device item holds.
    func storeLegacyOnDevice(_ identifier: String, replacing hasDeviceItem: Bool) -> Bool {
        if !hasDeviceItem {
            switch storage.add(identifier, synchronizable: false) {
            case .added:
                return true
            case .failed:
                return false
            case .alreadyExists:
                break
            }
        }
        return storage.replaceDeviceItem(with: identifier)
    }

    /// Stores a found or new identifier as this device's item. If another writer
    /// stored one first, that identifier wins, so one launch never sees two.
    func claimDeviceItem(
        _ identifier: String,
        source: AccountIdentifierSource,
        replacing hasDeviceItem: Bool
    ) -> AccountIdentifierResolution {
        if hasDeviceItem {
            return storage.replaceDeviceItem(with: identifier)
                ? .resolved(identifier: identifier, source: source)
                : .failed(failureError)
        }

        switch storage.add(identifier, synchronizable: false) {
        case .added:
            return .resolved(identifier: identifier, source: source)
        case .alreadyExists:
            if case let .value(value) = storage.read(synchronizable: false), let stored = Self.normalized(value) {
                return .resolved(identifier: stored, source: .device)
            }
            return .failed(failureError)
        case .failed:
            return .failed(failureError)
        }
    }

    /// Nothing has used the new identifier yet. If another phone's copy reached
    /// iCloud Keychain after the read, the device joins that account instead.
    func shareGenerated(_ generated: String) -> AccountIdentifierResolution {
        guard synchronizes, storage.add(generated, synchronizable: true) == .alreadyExists,
              case let .value(value) = storage.read(synchronizable: true),
              let synced = Self.normalized(value),
              synced != generated,
              storage.replaceDeviceItem(with: synced)
        else {
            return .resolved(identifier: generated, source: .generated)
        }
        return .resolved(identifier: synced, source: .iCloudKeychain)
    }

    /// Best effort: without iCloud Keychain the identifier stays on this device.
    /// An existing copy of another phone is kept.
    func addICloudCopy(_ identifier: String) {
        guard synchronizes else { return }
        _ = storage.add(identifier, synchronizable: true)
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.utf8.count <= maximumIdentifierByteCount,
              !trimmed.contains("\r"),
              !trimmed.contains("\n")
        else {
            return nil
        }
        return trimmed
    }
}

enum AccountIdentifierItemRead: Equatable, Sendable {
    case value(String)
    /// The item exists, but its data is not text.
    case unreadable
    case missing
    /// No definite answer: the device is locked or Keychain is not accessible.
    case unavailable
}

enum AccountIdentifierItemAdd: Equatable, Sendable {
    case added
    case alreadyExists
    case failed
}

protocol AccountIdentifierItemStorage: Sendable {
    func read(synchronizable: Bool) -> AccountIdentifierItemRead
    /// Adds the item only when there is none; an existing item is never replaced.
    func add(_ identifier: String, synchronizable: Bool) -> AccountIdentifierItemAdd
    func replaceDeviceItem(with identifier: String) -> Bool
}

struct SecurityAccountIdentifierItemStorage: AccountIdentifierItemStorage {
    let configuration: KeychainAccountIdentifierConfiguration

    func read(synchronizable: Bool) -> AccountIdentifierItemRead {
        var query = baseQuery(synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return .unreadable
            }
            return .value(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    func add(_ identifier: String, synchronizable: Bool) -> AccountIdentifierItemAdd {
        var item = baseQuery(synchronizable: synchronizable)
        item[kSecValueData as String] = Data(identifier.utf8)
        // Readable by a background launch after the first unlock. A `ThisDeviceOnly`
        // class would keep the item out of iCloud Keychain.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        switch SecItemAdd(item as CFDictionary, nil) {
        case errSecSuccess:
            return .added
        case errSecDuplicateItem:
            return .alreadyExists
        default:
            return .failed
        }
    }

    func replaceDeviceItem(with identifier: String) -> Bool {
        let query = baseQuery(synchronizable: false)
        let update = [kSecValueData as String: Data(identifier.utf8)]

        switch SecItemUpdate(query as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return add(identifier, synchronizable: false) == .added
        default:
            return false
        }
    }

    private func baseQuery(synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: configuration.account,
            kSecAttrSynchronizable as String: synchronizable
        ]
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
