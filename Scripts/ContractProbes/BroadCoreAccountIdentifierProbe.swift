import Foundation

/// In-memory stand-in for Keychain, so the probe never touches the real one.
/// `local` is this device's item, `synced` the iCloud Keychain item. Hooks run
/// right before an add, to interleave another writer the way a real race would.
private final class MemoryKeychain: AccountIdentifierItemStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var local: String?
    private var synced: String?
    private var localUnavailable = false
    private var syncedUnavailable = false
    private var localWritesFail = false
    private var syncedAccessCount = 0
    private var beforeLocalAdd: (() -> String?)?
    private var beforeSyncedAdd: (() -> String?)?

    init(local: String? = nil, synced: String? = nil) {
        self.local = local
        self.synced = synced
    }

    var localValue: String? {
        locked { local }
    }

    var syncedValue: String? {
        locked { synced }
    }

    var touchedICloud: Bool {
        locked { syncedAccessCount > 0 }
    }

    func setLocalUnavailable(_ unavailable: Bool) {
        locked { localUnavailable = unavailable }
    }

    func makeSyncedUnavailable() {
        locked { syncedUnavailable = true }
    }

    func setLocalWritesFail(_ fail: Bool) {
        locked { localWritesFail = fail }
    }

    /// Another writer stores this device's item between the read and the add.
    func interleaveLocalWriter(_ value: String) {
        locked { beforeLocalAdd = { value } }
    }

    /// Another phone's copy reaches iCloud Keychain between the read and the add.
    func interleaveOtherPhone(_ value: String) {
        locked { beforeSyncedAdd = { value } }
    }

    func read(synchronizable: Bool) -> AccountIdentifierItemRead {
        locked {
            if synchronizable {
                syncedAccessCount += 1
                if syncedUnavailable {
                    return .unavailable
                }
                return synced.map(AccountIdentifierItemRead.value) ?? .missing
            }
            if localUnavailable {
                return .unavailable
            }
            return local.map(AccountIdentifierItemRead.value) ?? .missing
        }
    }

    func add(_ identifier: String, synchronizable: Bool) -> AccountIdentifierItemAdd {
        locked {
            if synchronizable {
                syncedAccessCount += 1
                if let arrived = beforeSyncedAdd?() {
                    synced = arrived
                    beforeSyncedAdd = nil
                }
                guard !syncedUnavailable else { return .failed }
                guard synced == nil else { return .alreadyExists }
                synced = identifier
                return .added
            }
            if let arrived = beforeLocalAdd?() {
                local = arrived
                beforeLocalAdd = nil
            }
            guard !localUnavailable, !localWritesFail else { return .failed }
            guard local == nil else { return .alreadyExists }
            local = identifier
            return .added
        }
    }

    func replaceDeviceItem(with identifier: String) -> Bool {
        locked {
            guard !localUnavailable, !localWritesFail else { return false }
            local = identifier
            return true
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@main
enum BroadCoreAccountIdentifierProbe {
    private static let failure = AppError(
        kind: .unavailable,
        userMessage: "Keychain is not available yet.",
        diagnosticCode: "probe.account-identifier.unavailable",
        isRetryable: true
    )

    static func main() async {
        await checkFreshInstallGeneratesAndStoresEverywhere()
        await checkRelaunchKeepsTheDeviceIdentifier()
        await checkNewPhoneJoinsTheICloudAccount()
        await checkReinstallKeepsItsOwnIdentifierOverAnotherPhone()
        await checkLegacyIdentifierStaysMainAndIsShared()
        await checkLegacyNeverOverwritesAnotherPhoneInICloud()
        await checkInvalidLegacyIsIgnored()
        await checkLockedKeychainDoesNotStartAnotherAccount()
        await checkUnavailableICloudDoesNotStartAnotherAccount()
        await checkUnstoredIdentifierIsRefused()
        await checkUnstoredLegacyKeepsTheMigrationRetryable()
        await checkUnstoredICloudIdentifierIsRefused()
        await checkAnotherPhoneArrivingDuringGenerationIsJoined()
        await checkAnotherPhoneArrivingWhileSharingIsNotReplaced()
        await checkAnotherDeviceWriterWins()
        await checkDisabledSyncNeverTouchesICloud()
        await checkConcurrentCallsResolveOneIdentifier()
        print(
            "PASS: account identifier prefers the host and device items over iCloud Keychain, "
                + "fails instead of starting another account, returns only stored identifiers "
                + "and never replaces another phone's iCloud copy"
        )
    }

    private static func checkFreshInstallGeneratesAndStoresEverywhere() async {
        let keychain = MemoryKeychain()
        let outcome = await makeStore(keychain, makeIdentifier: { "generated-1" }).resolve()

        guard outcome == .resolved(identifier: "generated-1", source: .generated) else {
            fatalError("A fresh install must generate an identifier")
        }
        guard keychain.localValue == "generated-1", keychain.syncedValue == "generated-1" else {
            fatalError("A generated identifier must be stored on the device and in iCloud Keychain")
        }
    }

    private static func checkRelaunchKeepsTheDeviceIdentifier() async {
        let keychain = MemoryKeychain(local: "device-1", synced: "device-1")
        let outcome = await makeStore(keychain).resolve()

        guard outcome == .resolved(identifier: "device-1", source: .device) else {
            fatalError("A relaunch must resolve the identifier stored on this device")
        }
    }

    private static func checkNewPhoneJoinsTheICloudAccount() async {
        let keychain = MemoryKeychain(synced: "old-phone")
        let outcome = await makeStore(keychain).resolve()

        guard outcome == .resolved(identifier: "old-phone", source: .iCloudKeychain) else {
            fatalError("A new phone must join the account from iCloud Keychain")
        }
        guard keychain.localValue == "old-phone" else {
            fatalError("The joined identifier must become this device's own item")
        }
    }

    private static func checkReinstallKeepsItsOwnIdentifierOverAnotherPhone() async {
        let keychain = MemoryKeychain(local: "this-phone", synced: "other-phone")
        let outcome = await makeStore(keychain).resolve()

        guard outcome == .resolved(identifier: "this-phone", source: .device) else {
            fatalError("A reinstall must keep this device's identifier over iCloud Keychain")
        }
        guard keychain.syncedValue == "other-phone" else {
            fatalError("An identifier of another phone in iCloud Keychain must not be overwritten")
        }
    }

    private static func checkLegacyIdentifierStaysMainAndIsShared() async {
        let keychain = MemoryKeychain(local: "stale")
        let outcome = await makeStore(keychain, legacy: { "  legacy-1\n" }).resolve()

        guard outcome == .resolved(identifier: "legacy-1", source: .legacy) else {
            fatalError("The host's legacy identifier must stay the main one on this device")
        }
        guard keychain.localValue == "legacy-1", keychain.syncedValue == "legacy-1" else {
            fatalError("A legacy identifier must be stored on the device and shared through iCloud Keychain")
        }
    }

    private static func checkLegacyNeverOverwritesAnotherPhoneInICloud() async {
        let keychain = MemoryKeychain(synced: "other-phone")
        _ = await makeStore(keychain, legacy: { "legacy-1" }).resolve()

        guard keychain.syncedValue == "other-phone" else {
            fatalError("A legacy identifier must not take over an iCloud item of another phone")
        }
    }

    private static func checkInvalidLegacyIsIgnored() async {
        for invalid in ["", "   ", "two\nlines", String(repeating: "x", count: 1025)] {
            let keychain = MemoryKeychain(local: "device-1")
            let outcome = await makeStore(keychain, legacy: { invalid }).resolve()
            guard outcome == .resolved(identifier: "device-1", source: .device) else {
                fatalError("An empty, multiline or oversized legacy identifier must be ignored")
            }
        }
    }

    private static func checkLockedKeychainDoesNotStartAnotherAccount() async {
        let keychain = MemoryKeychain(local: "device-1")
        keychain.setLocalUnavailable(true)

        guard await makeStore(keychain).resolve() == .failed(failure) else {
            fatalError("A locked Keychain must fail instead of generating another identifier")
        }
        guard keychain.syncedValue == nil else {
            fatalError("A failed resolution must not write to iCloud Keychain")
        }
    }

    private static func checkUnavailableICloudDoesNotStartAnotherAccount() async {
        let keychain = MemoryKeychain()
        keychain.makeSyncedUnavailable()

        guard await makeStore(keychain).resolve() == .failed(failure) else {
            fatalError("An unanswered iCloud read must fail instead of generating another identifier")
        }
        guard keychain.localValue == nil else {
            fatalError("A failed resolution must not store a new identifier on the device")
        }
    }

    private static func checkUnstoredIdentifierIsRefused() async {
        let keychain = MemoryKeychain()
        keychain.setLocalWritesFail(true)

        guard await makeStore(keychain).resolve() == .failed(failure) else {
            fatalError("An identifier that could not be stored on the device must not be returned")
        }
    }

    private static func checkUnstoredLegacyKeepsTheMigrationRetryable() async {
        let keychain = MemoryKeychain()
        keychain.setLocalWritesFail(true)
        let store = makeStore(keychain, legacy: { "legacy-1" })

        guard await store.resolve() == .failed(failure) else {
            fatalError("A legacy identifier that could not be stored must not complete the migration")
        }

        keychain.setLocalWritesFail(false)
        guard await store.resolve() == .resolved(identifier: "legacy-1", source: .legacy),
              keychain.localValue == "legacy-1"
        else {
            fatalError("A failed migration must be retried and complete once Keychain accepts the item")
        }
    }

    private static func checkUnstoredICloudIdentifierIsRefused() async {
        let keychain = MemoryKeychain(synced: "old-phone")
        keychain.setLocalWritesFail(true)

        guard await makeStore(keychain).resolve() == .failed(failure) else {
            fatalError("An iCloud identifier that could not be stored on the device must not be returned")
        }
    }

    private static func checkAnotherPhoneArrivingDuringGenerationIsJoined() async {
        let keychain = MemoryKeychain()
        keychain.interleaveOtherPhone("other-phone")
        let outcome = await makeStore(keychain, makeIdentifier: { "generated-1" }).resolve()

        guard outcome == .resolved(identifier: "other-phone", source: .iCloudKeychain) else {
            fatalError("An iCloud copy arriving before the new identifier is used must be joined")
        }
        guard keychain.syncedValue == "other-phone", keychain.localValue == "other-phone" else {
            fatalError("The arriving iCloud copy must be kept and become this device's item")
        }
    }

    private static func checkAnotherPhoneArrivingWhileSharingIsNotReplaced() async {
        let keychain = MemoryKeychain(local: "this-phone")
        keychain.interleaveOtherPhone("other-phone")
        let outcome = await makeStore(keychain).resolve()

        guard outcome == .resolved(identifier: "this-phone", source: .device) else {
            fatalError("The device must keep its identifier when another phone's copy arrives")
        }
        guard keychain.syncedValue == "other-phone" else {
            fatalError("An iCloud copy that appeared before the add must not be replaced")
        }
    }

    private static func checkAnotherDeviceWriterWins() async {
        let keychain = MemoryKeychain()
        keychain.interleaveLocalWriter("stored-first")
        let outcome = await makeStore(keychain, makeIdentifier: { "generated-1" }).resolve()

        guard outcome == .resolved(identifier: "stored-first", source: .device),
              keychain.localValue == "stored-first"
        else {
            fatalError("A device item stored first by another writer must win over a new identifier")
        }
    }

    private static func checkDisabledSyncNeverTouchesICloud() async {
        let keychain = MemoryKeychain(synced: "other-phone")
        let outcome = await makeStore(keychain, synchronizes: false, makeIdentifier: { "local-only" }).resolve()

        guard outcome == .resolved(identifier: "local-only", source: .generated) else {
            fatalError("With sync disabled an iCloud item must not be joined")
        }
        guard !keychain.touchedICloud else {
            fatalError("With sync disabled iCloud Keychain must not be read or written")
        }
    }

    private static func checkConcurrentCallsResolveOneIdentifier() async {
        let keychain = MemoryKeychain()
        let store = makeStore(keychain, makeIdentifier: { UUID().uuidString })

        async let first = store.resolve()
        async let second = store.resolve()
        let outcomes = await [first, second]

        guard outcomes[0] == outcomes[1], outcomes[0].identifier == keychain.localValue else {
            fatalError("Concurrent calls must resolve one identifier")
        }
    }

    private static func makeStore(
        _ keychain: MemoryKeychain,
        synchronizes: Bool = true,
        legacy: @escaping @Sendable () -> String? = { nil },
        makeIdentifier: @escaping @Sendable () -> String = { "generated" }
    ) -> KeychainAccountIdentifierStore {
        KeychainAccountIdentifierStore(
            storage: keychain,
            synchronizes: synchronizes,
            failureError: failure,
            legacyIdentifier: legacy,
            makeIdentifier: makeIdentifier
        )
    }
}
