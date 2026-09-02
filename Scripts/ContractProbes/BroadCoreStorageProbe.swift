import Foundation

@main
enum BroadCoreStorageProbe {
    static func main() async throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BroadCoreStorageProbe-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directoryURL) }

        let store = FileSystemKeyValueStore(
            directoryURL: directoryURL,
            namespace: "contract-probe",
            maximumDataSize: 4
        )

        let initialSnapshot = try await store.read("catalog")
        try expect(initialSnapshot == .missing, "new file store starts empty")

        let first = Data([1, 2, 3])
        try await store.write(first, forKey: "catalog")
        let firstSnapshot = try await store.read("catalog")
        try expect(firstSnapshot == .data(first), "file store reads written data")

        let rejected = try await store.write(
            Data([4]),
            forKey: "catalog",
            ifMatching: .missing
        )
        try expect(!rejected, "compare-and-swap rejects a stale snapshot")

        let replaced = try await store.write(
            Data([4]),
            forKey: "catalog",
            ifMatching: firstSnapshot
        )
        try expect(replaced, "compare-and-swap accepts the current snapshot")

        do {
            try await store.write(Data(repeating: 0, count: 5), forKey: "oversized")
            throw ProbeError.failed("oversized value must be rejected")
        } catch KeyValueStoreError.valueTooLarge(actualBytes: 5, maximumBytes: 4) {
            // Expected.
        }

        let currentSnapshot = try await store.read("catalog")
        let removed = try await store.remove("catalog", ifMatching: currentSnapshot)
        try expect(removed, "conditional removal accepts the current snapshot")
        let removedSnapshot = try await store.read("catalog")
        try expect(removedSnapshot == .missing, "removed value is absent")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ contract: String) throws {
        guard condition() else {
            throw ProbeError.failed(contract)
        }
    }

    private enum ProbeError: Error {
        case failed(String)
    }
}
