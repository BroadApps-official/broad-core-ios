import Foundation

/// In-memory stand-in for Keychain, so the probe never touches the real one.
/// `local` is this device's item, `synced` the iCloud Keychain item.
private final class MemoryKeychain: AccountIdentifierItemStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var local: String?
    private var synced: String?
    private var localUnavailable = false
    private var localWritesFail = false
    private var syncedAccessCount = 0

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

    func makeLocalUnavailable() {
        locked { localUnavailable = true }
    }

    func makeLocalWritesFail() {
        locked { localWritesFail = true }
    }

    func read(synchronizable: Bool) -> AccountIdentifierItemRead {
        locked {
            if synchronizable {
                syncedAccessCount += 1
                return synced.map(AccountIdentifierItemRead.value) ?? .missing
            }
            if localUnavailable {
                return .unavailable
            }
            return local.map(AccountIdentifierItemRead.value) ?? .missing
        }
    }

    func write(_ identifier: String, synchronizable: Bool) -> Bool {
        locked {
            if synchronizable {
                syncedAccessCount += 1
                synced = identifier
                return true
            }
            if localUnavailable || localWritesFail {
                return false
            }
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
        await checkUnstoredIdentifierIsRefused()
        await checkDisabledSyncNeverTouchesICloud()
        await checkConcurrentCallsResolveOneIdentifier()
        print(
            "PASS: account identifier prefers the host and device items over iCloud Keychain, "
                + "joins the iCloud account on a new phone and never returns an unstored identifier"
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
        keychain.makeLocalUnavailable()
        let store = makeStore(keychain)

        guard await store.resolve() == .failed(failure) else {
            fatalError("A locked Keychain must fail instead of generating another identifier")
        }
        guard keychain.syncedValue == nil else {
            fatalError("A failed resolution must not write to iCloud Keychain")
        }
    }

    private static func checkUnstoredIdentifierIsRefused() async {
        let keychain = MemoryKeychain()
        keychain.makeLocalWritesFail()

        guard await makeStore(keychain).resolve() == .failed(failure) else {
            fatalError("An identifier that could not be stored on the device must not be returned")
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
        let counter = MemoryKeychain()
        let store = makeStore(counter, makeIdentifier: { UUID().uuidString })

        async let first = store.resolve()
        async let second = store.resolve()
        let outcomes = await [first, second]

        guard outcomes[0] == outcomes[1], outcomes[0].identifier == counter.localValue else {
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
