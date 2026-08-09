public enum CacheMissReason: Sendable, Equatable {
    case notFound
    case corrupted
    case schemaMismatch(expected: String, actual: String?)
    case versionMismatch(expected: Int, actual: Int)
}

public enum CacheReadResult<Value: Codable & Sendable>: Sendable {
    case fresh(CacheEnvelope<Value>)
    case stale(CacheEnvelope<Value>)
    case missing(CacheMissReason)
}

extension CacheReadResult: Equatable where Value: Equatable {}
