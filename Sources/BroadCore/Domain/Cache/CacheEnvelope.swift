import Foundation

public struct CacheEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value
    public let schemaIdentifier: String
    public let version: Int
    public let savedAt: Date
    public let expiresAt: Date

    public init(
        value: Value,
        schemaIdentifier: String,
        version: Int,
        savedAt: Date,
        expiresAt: Date
    ) {
        self.value = value
        self.schemaIdentifier = schemaIdentifier
        self.version = version
        self.savedAt = savedAt
        self.expiresAt = expiresAt
    }
}

extension CacheEnvelope: Equatable where Value: Equatable {}
