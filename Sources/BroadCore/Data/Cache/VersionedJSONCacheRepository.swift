import Foundation

public actor VersionedJSONCacheRepository: CacheRepositoryProtocol {
    public static let defaultMaximumEncodedSize = 512 * 1024

    private let keyValueStore: any KeyValueStoreProtocol
    private let clock: CacheClock
    private let maximumEncodedSize: Int
    private let logger: any BroadLoggerProtocol

    public init(
        keyValueStore: any KeyValueStoreProtocol,
        clock: CacheClock = .system,
        maximumEncodedSize: Int = VersionedJSONCacheRepository.defaultMaximumEncodedSize,
        logger: any BroadLoggerProtocol = NoOpBroadLogger()
    ) {
        precondition(maximumEncodedSize > 0, "Maximum encoded cache size must be greater than zero")

        self.keyValueStore = keyValueStore
        self.clock = clock
        self.maximumEncodedSize = maximumEncodedSize
        self.logger = logger
    }

    public func read<Value: Codable & Sendable>(
        _ key: CacheKey<Value>
    ) async throws -> CacheReadResult<Value> {
        let storageKey = storageKey(for: key)
        let snapshot: KeyValueStoreEntry

        do {
            snapshot = try await keyValueStore.read(storageKey)
        } catch {
            logger.log(.cacheOperationFailed(operation: .read, failure: .storage))
            throw error
        }

        switch snapshot {
        case .missing:
            return missingResult(.notFound)
        case .invalidType, .oversizedData:
            await removeIfRequested(
                storageKey,
                snapshot: snapshot,
                action: key.policy.corruptedEntryAction
            )
            return missingResult(.corrupted)
        case let .data(data):
            guard data.count <= maximumEncodedSize else {
                await removeIfRequested(
                    storageKey,
                    snapshot: snapshot,
                    action: key.policy.corruptedEntryAction
                )
                return missingResult(.corrupted)
            }

            return await decode(
                data,
                snapshot: snapshot,
                storageKey: storageKey,
                key: key
            )
        }
    }

    public func write<Value: Codable & Sendable>(
        _ value: Value,
        for key: CacheKey<Value>
    ) async throws {
        let data = try encodedEnvelope(value, for: key)

        do {
            try await keyValueStore.write(data, forKey: storageKey(for: key))
            logger.log(.cacheOperationCompleted(.write))
        } catch {
            logger.log(.cacheOperationFailed(operation: .write, failure: cacheFailure(from: error)))
            throw error
        }
    }

    public func insertIfMissing<Value: Codable & Equatable & Sendable>(
        _ value: Value,
        for key: CacheKey<Value>
    ) async throws -> Bool {
        let data = try encodedEnvelope(value, for: key)
        let storageKey = storageKey(for: key)
        let inserted = try await keyValueStore.write(
            data,
            forKey: storageKey,
            ifMatching: .missing
        )
        if inserted {
            logger.log(.cacheOperationCompleted(.write))
        }
        return inserted
    }

    public func replace<Value: Codable & Equatable & Sendable>(
        _ value: Value,
        ifMatching expectedValue: Value,
        for key: CacheKey<Value>
    ) async throws -> Bool {
        let storageKey = storageKey(for: key)
        let snapshot = try await keyValueStore.read(storageKey)
        guard snapshotContains(expectedValue, snapshot: snapshot, key: key) else {
            return false
        }
        let data = try encodedEnvelope(value, for: key)
        let replaced = try await keyValueStore.write(
            data,
            forKey: storageKey,
            ifMatching: snapshot
        )
        if replaced {
            logger.log(.cacheOperationCompleted(.write))
        }
        return replaced
    }

    public func remove<Value: Codable & Sendable>(
        _ key: CacheKey<Value>
    ) async throws {
        do {
            try await keyValueStore.remove(storageKey(for: key))
            logger.log(.cacheOperationCompleted(.remove))
        } catch {
            logger.log(.cacheOperationFailed(operation: .remove, failure: .storage))
            throw error
        }
    }

    public func remove<Value: Codable & Equatable & Sendable>(
        _ key: CacheKey<Value>,
        ifMatching expectedValue: Value
    ) async throws -> Bool {
        let storageKey = storageKey(for: key)
        let snapshot = try await keyValueStore.read(storageKey)
        guard snapshotContains(expectedValue, snapshot: snapshot, key: key) else {
            return false
        }
        let removed = try await keyValueStore.remove(
            storageKey,
            ifMatching: snapshot
        )
        if removed {
            logger.log(.cacheOperationCompleted(.remove))
        }
        return removed
    }
}

private extension VersionedJSONCacheRepository {
    private func encodedEnvelope<Value: Codable & Sendable>(
        _ value: Value,
        for key: CacheKey<Value>
    ) throws -> Data {
        let savedAt = clock.now()
        let expirationTimestamp = savedAt.timeIntervalSinceReferenceDate
            + key.policy.timeToLive
        guard savedAt.timeIntervalSinceReferenceDate.isFinite,
              expirationTimestamp.isFinite
        else {
            logger.log(.cacheOperationFailed(operation: .write, failure: .invalidTimestamp))
            throw CacheRepositoryError.invalidTimestamp
        }

        let envelope = CacheEnvelope(
            value: value,
            schemaIdentifier: key.schemaIdentifier,
            version: key.version,
            savedAt: savedAt,
            expiresAt: Date(timeIntervalSinceReferenceDate: expirationTimestamp)
        )
        let data: Data
        do {
            data = try Self.makeEncoder().encode(envelope)
        } catch {
            logger.log(.cacheOperationFailed(operation: .write, failure: .encoding))
            throw CacheRepositoryError.encodingFailed
        }
        guard data.count <= maximumEncodedSize else {
            logger.log(.cacheOperationFailed(operation: .write, failure: .valueTooLarge))
            throw KeyValueStoreError.valueTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumEncodedSize
            )
        }
        return data
    }

    private func snapshotContains<Value: Codable & Equatable & Sendable>(
        _ expectedValue: Value,
        snapshot: KeyValueStoreEntry,
        key: CacheKey<Value>
    ) -> Bool {
        guard case let .data(data) = snapshot,
              data.count <= maximumEncodedSize,
              let envelope = try? Self.makeDecoder().decode(
                  CacheEnvelope<Value>.self,
                  from: data
              ),
              envelope.schemaIdentifier == key.schemaIdentifier,
              envelope.version == key.version,
              envelope.expiresAt >= envelope.savedAt,
              envelope.value == expectedValue
        else {
            return false
        }
        return true
    }

    private func decode<Value: Codable & Sendable>(
        _ data: Data,
        snapshot: KeyValueStoreEntry,
        storageKey: String,
        key: CacheKey<Value>
    ) async -> CacheReadResult<Value> {
        guard let identity = try? Self.makeDecoder().decode(CacheEnvelopeIdentity.self, from: data) else {
            await removeIfRequested(
                storageKey,
                snapshot: snapshot,
                action: key.policy.corruptedEntryAction
            )
            return missingResult(.corrupted)
        }

        if let mismatch = identityMismatch(identity, key: key) {
            await removeIfRequested(
                storageKey,
                snapshot: snapshot,
                action: mismatch.action
            )
            return missingResult(mismatch.reason)
        }

        let envelope: CacheEnvelope<Value>

        do {
            envelope = try Self.makeDecoder().decode(CacheEnvelope<Value>.self, from: data)
        } catch {
            await removeIfRequested(
                storageKey,
                snapshot: snapshot,
                action: key.policy.corruptedEntryAction
            )
            return missingResult(.corrupted)
        }

        guard envelope.expiresAt >= envelope.savedAt else {
            await removeIfRequested(
                storageKey,
                snapshot: snapshot,
                action: key.policy.corruptedEntryAction
            )
            return missingResult(.corrupted)
        }

        let now = clock.now()
        guard now >= envelope.savedAt, now < envelope.expiresAt else {
            logger.log(.cacheReadCompleted(.stale))
            return .stale(envelope)
        }

        logger.log(.cacheReadCompleted(.fresh))
        return .fresh(envelope)
    }

    private func identityMismatch<Value: Codable & Sendable>(
        _ identity: CacheEnvelopeIdentity,
        key: CacheKey<Value>
    ) -> (reason: CacheMissReason, action: InvalidCacheEntryAction)? {
        guard identity.schemaIdentifier == key.schemaIdentifier else {
            return (
                .schemaMismatch(
                    expected: key.schemaIdentifier,
                    actual: identity.schemaIdentifier
                ),
                key.policy.schemaMismatchAction
            )
        }

        guard identity.version == key.version else {
            return (
                .versionMismatch(expected: key.version, actual: identity.version),
                key.policy.versionMismatchAction
            )
        }

        return nil
    }

    private func storageKey<Value: Codable & Sendable>(
        for key: CacheKey<Value>
    ) -> String {
        "\(key.schemaIdentifier.utf8.count)#\(key.schemaIdentifier)#\(key.name)"
    }

    private func removeIfRequested(
        _ key: String,
        snapshot: KeyValueStoreEntry,
        action: InvalidCacheEntryAction
    ) async {
        guard action == .remove else {
            return
        }

        do {
            _ = try await keyValueStore.remove(key, ifMatching: snapshot)
            logger.log(.cacheOperationCompleted(.cleanup))
        } catch {
            logger.log(.cacheOperationFailed(operation: .cleanup, failure: .storage))
        }
    }

    private func missingResult<Value: Codable & Sendable>(
        _ reason: CacheMissReason
    ) -> CacheReadResult<Value> {
        logger.log(.cacheReadCompleted(logResult(for: reason)))
        return .missing(reason)
    }

    private func logResult(for reason: CacheMissReason) -> BroadLogCacheReadResult {
        switch reason {
        case .notFound:
            .notFound
        case .corrupted:
            .corrupted
        case .schemaMismatch:
            .schemaMismatch
        case .versionMismatch:
            .versionMismatch
        }
    }

    private func cacheFailure(from error: any Error) -> BroadLogCacheFailure {
        if case KeyValueStoreError.valueTooLarge = error {
            return .valueTooLarge
        }

        return .storage
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private struct CacheEnvelopeIdentity: Decodable {
    let version: Int
    let schemaIdentifier: String?
}
