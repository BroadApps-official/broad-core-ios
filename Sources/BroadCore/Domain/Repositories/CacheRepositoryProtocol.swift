public enum CacheRepositoryError: Error, Sendable, Equatable {
    case encodingFailed
    case invalidTimestamp
}

public protocol CacheRepositoryProtocol: Sendable {
    func read<Value: Codable & Sendable>(
        _ key: CacheKey<Value>
    ) async throws -> CacheReadResult<Value>

    func write<Value: Codable & Sendable>(
        _ value: Value,
        for key: CacheKey<Value>
    ) async throws

    /// Atomically writes only when no raw storage entry exists. Corrupted or
    /// schema-mismatched data is still "existing" and therefore fails closed.
    func insertIfMissing<Value: Codable & Equatable & Sendable>(
        _ value: Value,
        for key: CacheKey<Value>
    ) async throws -> Bool

    func replace<Value: Codable & Equatable & Sendable>(
        _ value: Value,
        ifMatching expectedValue: Value,
        for key: CacheKey<Value>
    ) async throws -> Bool

    func remove<Value: Codable & Sendable>(
        _ key: CacheKey<Value>
    ) async throws

    func remove<Value: Codable & Equatable & Sendable>(
        _ key: CacheKey<Value>,
        ifMatching expectedValue: Value
    ) async throws -> Bool
}
