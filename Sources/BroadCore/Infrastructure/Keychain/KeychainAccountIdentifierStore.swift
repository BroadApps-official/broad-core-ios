import Foundation
import Security

/// Where the account identifier is kept in Keychain.
public struct KeychainAccountIdentifierConfiguration: Equatable, Sendable {
    public let service: String
    public let account: String
    /// A missing access group means the app's default Keychain access group.
    public let accessGroup: String?
    /// Also keep a copy in iCloud Keychain, so a new phone on the same Apple ID
    /// resolves the same account. `false` keeps the identifier on this device only.
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
/// 2. This device's own item. It survives a reinstall and wins over iCloud Keychain,
///    where another phone on the same Apple ID may have put a different identifier.
/// 3. The item from iCloud Keychain. The device has none of its own, so it is a new
///    phone of an existing user and joins that account.
/// 4. A new identifier, returned only after it is stored on this device.
///
/// A copy is written to iCloud Keychain only when none is there yet, so two phones
/// never take the item over from each other. The identifier is never logged.
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
        let own: String?
        switch storage.read(synchronizable: false) {
        case let .value(value):
            own = Self.normalized(value)
        case .missing:
            own = nil
        case .unavailable:
            // Keychain is locked or unavailable. A new identifier here would start a
            // second account for someone who already has one.
            return .failed(failureError)
        }

        if let legacy = Self.normalized(legacyIdentifier()) {
            if own != legacy {
                _ = storage.write(legacy, synchronizable: false)
            }
            shareIfICloudIsEmpty(legacy)
            return .resolved(identifier: legacy, source: .legacy)
        }

        if let own {
            shareIfICloudIsEmpty(own)
            return .resolved(identifier: own, source: .device)
        }

        if synchronizes,
           case let .value(value) = storage.read(synchronizable: true),
           let synced = Self.normalized(value) {
            _ = storage.write(synced, synchronizable: false)
            return .resolved(identifier: synced, source: .iCloudKeychain)
        }

        guard let generated = Self.normalized(makeIdentifier()),
              storage.write(generated, synchronizable: false)
        else {
            // An identifier that is not stored anywhere changes on the next launch.
            return .failed(failureError)
        }
        shareIfICloudIsEmpty(generated)
        return .resolved(identifier: generated, source: .generated)
    }

    func shareIfICloudIsEmpty(_ identifier: String) {
        guard synchronizes, storage.read(synchronizable: true) == .missing else { return }
        // Best effort: an unsigned build or disabled iCloud Keychain keeps the identifier local.
        _ = storage.write(identifier, synchronizable: true)
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
    case missing
    case unavailable
}

protocol AccountIdentifierItemStorage: Sendable {
    func read(synchronizable: Bool) -> AccountIdentifierItemRead
    func write(_ identifier: String, synchronizable: Bool) -> Bool
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
                return .missing
            }
            return .value(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .unavailable
        }
    }

    func write(_ identifier: String, synchronizable: Bool) -> Bool {
        let query = baseQuery(synchronizable: synchronizable)
        let data = Data(identifier.utf8)

        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        guard status == errSecItemNotFound else {
            return false
        }

        var item = query
        item[kSecValueData as String] = data
        // Readable by a background launch after the first unlock. A `ThisDeviceOnly`
        // class would keep the item out of iCloud Keychain.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
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
