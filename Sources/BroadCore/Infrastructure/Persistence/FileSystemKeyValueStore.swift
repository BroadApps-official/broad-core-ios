import CryptoKit
import Foundation

/// File-backed storage for cache payloads that are too large for preference storage.
public actor FileSystemKeyValueStore: KeyValueStoreProtocol {
    public static let defaultMaximumDataSize = 8 * 1024 * 1024

    private let directoryURL: URL
    private let namespace: String
    private let maximumDataSize: Int
    private let fileManager: FileManager

    public init(
        directoryURL: URL,
        namespace: String,
        maximumDataSize: Int = FileSystemKeyValueStore.defaultMaximumDataSize
    ) {
        precondition(directoryURL.isFileURL, "Storage directory must be a file URL")
        precondition(!namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Storage namespace must not be empty")
        precondition(maximumDataSize > 0, "Maximum storage data size must be greater than zero")

        self.directoryURL = directoryURL
        self.namespace = namespace
        self.maximumDataSize = maximumDataSize
        fileManager = .default
    }

    public func read(_ key: String) throws -> KeyValueStoreEntry {
        let fileURL = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .missing
        }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= maximumDataSize else {
            return oversizedEntry(for: data)
        }
        return .data(data)
    }

    public func write(_ data: Data, forKey key: String) throws {
        try validateSize(data)
        try prepareDirectory()
        try data.write(to: fileURL(forKey: key), options: .atomic)
    }

    public func write(
        _ data: Data,
        forKey key: String,
        ifMatching snapshot: KeyValueStoreEntry
    ) throws -> Bool {
        try validateSize(data)
        guard try read(key) == snapshot else {
            return false
        }
        try prepareDirectory()
        try data.write(to: fileURL(forKey: key), options: .atomic)
        return true
    }

    public func remove(_ key: String) throws {
        let fileURL = fileURL(forKey: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
    }

    public func remove(
        _ key: String,
        ifMatching snapshot: KeyValueStoreEntry
    ) throws -> Bool {
        guard try read(key) == snapshot else {
            return false
        }
        try remove(key)
        return true
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(forKey key: String) -> URL {
        let identifier = "\(namespace.utf8.count)#\(namespace)#\(key)"
        let digest = SHA256.hash(data: Data(identifier.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func validateSize(_ data: Data) throws {
        guard data.count <= maximumDataSize else {
            throw KeyValueStoreError.valueTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumDataSize
            )
        }
    }

    private func oversizedEntry(for data: Data) -> KeyValueStoreEntry {
        .oversizedData(
            fingerprint: Data(SHA256.hash(data: data)),
            actualBytes: data.count,
            maximumBytes: maximumDataSize
        )
    }
}
