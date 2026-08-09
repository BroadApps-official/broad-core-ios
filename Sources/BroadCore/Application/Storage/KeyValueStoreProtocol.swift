import Foundation

public enum KeyValueStoreEntry: Sendable, Equatable {
    case missing
    case data(Data)
    case oversizedData(fingerprint: Data, actualBytes: Int, maximumBytes: Int)
    case invalidType(serializedValue: Data)
}

public enum KeyValueStoreError: Error, Sendable, Equatable {
    case valueTooLarge(actualBytes: Int, maximumBytes: Int)
}

public protocol KeyValueStoreProtocol: Sendable {
    func read(_ key: String) async throws -> KeyValueStoreEntry
    func write(_ data: Data, forKey key: String) async throws
    @discardableResult
    func write(
        _ data: Data,
        forKey key: String,
        ifMatching snapshot: KeyValueStoreEntry
    ) async throws -> Bool
    func remove(_ key: String) async throws
    @discardableResult
    func remove(
        _ key: String,
        ifMatching snapshot: KeyValueStoreEntry
    ) async throws -> Bool
}
