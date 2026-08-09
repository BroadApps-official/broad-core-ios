import CryptoKit
import Foundation

public actor UserDefaultsKeyValueStore: KeyValueStoreProtocol {
    public static let defaultMaximumDataSize = 512 * 1024

    private let userDefaults: UserDefaults
    private let namespace: String
    private let maximumDataSize: Int

    public init(
        suiteName: String? = nil,
        namespace: String,
        maximumDataSize: Int = UserDefaultsKeyValueStore.defaultMaximumDataSize
    ) {
        precondition(!namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Storage namespace must not be empty")
        precondition(maximumDataSize > 0, "Maximum storage data size must be greater than zero")

        if let suiteName {
            guard let userDefaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to create UserDefaults suite")
            }
            self.userDefaults = userDefaults
        } else {
            userDefaults = .standard
        }

        self.namespace = namespace
        self.maximumDataSize = maximumDataSize
    }

    public func read(_ key: String) -> KeyValueStoreEntry {
        entry(forKey: namespaced(key))
    }

    public func write(_ data: Data, forKey key: String) throws {
        guard data.count <= maximumDataSize else {
            throw KeyValueStoreError.valueTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumDataSize
            )
        }

        userDefaults.set(data, forKey: namespaced(key))
    }

    public func write(
        _ data: Data,
        forKey key: String,
        ifMatching snapshot: KeyValueStoreEntry
    ) throws -> Bool {
        guard data.count <= maximumDataSize else {
            throw KeyValueStoreError.valueTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumDataSize
            )
        }
        let storageKey = namespaced(key)
        guard entry(forKey: storageKey) == snapshot else {
            return false
        }
        userDefaults.set(data, forKey: storageKey)
        return true
    }

    public func remove(_ key: String) {
        userDefaults.removeObject(forKey: namespaced(key))
    }

    public func remove(
        _ key: String,
        ifMatching snapshot: KeyValueStoreEntry
    ) -> Bool {
        let storageKey = namespaced(key)
        guard entry(forKey: storageKey) == snapshot else {
            return false
        }

        userDefaults.removeObject(forKey: storageKey)
        return true
    }

    private func namespaced(_ key: String) -> String {
        "\(namespace.utf8.count)#\(namespace)#\(key)"
    }

    private func entry(forKey key: String) -> KeyValueStoreEntry {
        guard let object = userDefaults.object(forKey: key) else {
            return .missing
        }

        guard let data = object as? Data else {
            let serializedValue = serializedPropertyList(object)
            guard serializedValue.count <= maximumDataSize else {
                return oversizedEntry(for: serializedValue)
            }
            return .invalidType(serializedValue: serializedValue)
        }

        guard data.count <= maximumDataSize else {
            return oversizedEntry(for: data)
        }

        return .data(data)
    }

    private func serializedPropertyList(_ value: Any) -> Data {
        if let data = try? PropertyListSerialization.data(
            fromPropertyList: value,
            format: .binary,
            options: 0
        ) {
            return data
        }

        return Data(String(reflecting: type(of: value)).utf8)
    }

    private func oversizedEntry(for data: Data) -> KeyValueStoreEntry {
        .oversizedData(
            fingerprint: Data(SHA256.hash(data: data)),
            actualBytes: data.count,
            maximumBytes: maximumDataSize
        )
    }
}
