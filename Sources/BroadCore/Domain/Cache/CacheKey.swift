import Foundation

public struct CacheKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let schemaIdentifier: String
    public let version: Int
    public let policy: CachePolicy

    public init(
        name: String,
        schemaIdentifier: String,
        version: Int,
        policy: CachePolicy
    ) {
        precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Cache key name must not be empty")
        precondition(
            !schemaIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Cache schema identifier must not be empty"
        )
        precondition(version > 0, "Cache key version must be greater than zero")

        self.name = name
        self.schemaIdentifier = schemaIdentifier
        self.version = version
        self.policy = policy
    }
}

extension CacheKey: Equatable {}
