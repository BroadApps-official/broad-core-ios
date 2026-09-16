import Foundation

/// A single debug switch: a persisted boolean that a scheme launch argument can
/// force on for one run.
///
/// A flag is identified by a short `key` and an optional `launchArgument` such as
/// `-debug-force-premium`. `defaultValue` is returned until the switch has been
/// written, so a switch that should start on (for example local purchases in a
/// debug build) can model that without a first-run write.
public struct DebugFlag: Equatable, Sendable {
    /// Storage key within the backing key-value store.
    public let key: String
    /// Launch argument that forces the flag on for the current run, if any.
    public let launchArgument: String?
    /// Value returned before the flag has been written.
    public let defaultValue: Bool

    public init(
        key: String,
        launchArgument: String? = nil,
        defaultValue: Bool = false
    ) {
        precondition(
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Debug flag key must not be empty"
        )
        if let launchArgument {
            precondition(
                !launchArgument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Debug flag launch argument must not be empty"
            )
        }
        self.key = key
        self.launchArgument = launchArgument
        self.defaultValue = defaultValue
    }
}

/// Debug-build switches persisted through a ``KeyValueStoreProtocol``, each
/// optionally forced on by a scheme launch argument.
///
/// Persistence and key namespacing are delegated to the injected store, so a
/// debug build never reads switches another app left behind. The store carries no
/// policy of its own: a host declares its ``DebugFlag`` values, reads them to
/// branch behavior, and offers toggles from a debug menu, all under `#if DEBUG`.
/// A Release build simply never constructs one.
public struct DebugFlagStore: Sendable {
    private let store: any KeyValueStoreProtocol
    private let arguments: [String]

    /// - Parameters:
    ///   - store: backing key-value store; provides persistence and namespacing.
    ///   - arguments: process arguments scanned for launch-argument overrides.
    public init(
        store: any KeyValueStoreProtocol,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.store = store
        self.arguments = arguments
    }

    /// Whether the flag is on: a matching launch argument forces `true`; otherwise
    /// the persisted value, or the flag's `defaultValue` before it has been written
    /// (or if the stored value cannot be read back).
    public func isOn(_ flag: DebugFlag) async -> Bool {
        if let launchArgument = flag.launchArgument, arguments.contains(launchArgument) {
            return true
        }

        guard
            case let .data(data) = await (try? store.read(flag.key)) ?? .missing,
            let firstByte = data.first
        else {
            return flag.defaultValue
        }
        return firstByte != 0
    }

    /// Persists the flag's value for later runs.
    public func set(_ flag: DebugFlag, _ isOn: Bool) async {
        try? await store.write(Data([isOn ? 1 : 0]), forKey: flag.key)
    }

    /// Removes the persisted value for each flag, restoring its `defaultValue`.
    public func reset(_ flags: [DebugFlag]) async {
        for flag in flags {
            try? await store.remove(flag.key)
        }
    }

    /// Reads every flag once and hands back a value that answers synchronously.
    ///
    /// A composition root builds its dependency graph in one synchronous pass,
    /// and a debug switch usually decides which dependency is built at all. The
    /// store itself cannot answer there — its backing key-value store is async —
    /// so a host reads the switches once, before composing, and branches on the
    /// snapshot. Without this, every application keeps a second, synchronous
    /// store of its own next to this one.
    ///
    /// The snapshot does not follow later writes: take a new one after ``set(_:_:)``
    /// if the same run has to see the change.
    public func snapshot(of flags: [DebugFlag]) async -> DebugFlagSnapshot {
        var values: [String: Bool] = [:]
        values.reserveCapacity(flags.count)
        for flag in flags {
            values[flag.key] = await isOn(flag)
        }
        return DebugFlagSnapshot(values: values, arguments: arguments)
    }
}

/// Debug switches read once, answering without `await`.
///
/// Built by ``DebugFlagStore/snapshot(of:)``, and answering exactly as the store
/// would: a launch argument still forces its flag on, and a flag the snapshot was
/// not asked for falls back to its own `defaultValue`. Two answers for the same
/// flag in the same run would be a trap, not a convenience.
public struct DebugFlagSnapshot: Equatable, Sendable {
    private let values: [String: Bool]
    private let arguments: [String]

    init(values: [String: Bool], arguments: [String]) {
        self.values = values
        self.arguments = arguments
    }

    /// A snapshot with the listed flags on and every other flag at its own
    /// `defaultValue`.
    ///
    /// For a SwiftUI preview or any other place that has to stand in for a store
    /// it cannot read. Launch arguments are not consulted.
    public init(on flags: [DebugFlag]) {
        values = flags.reduce(into: [:]) { values, flag in
            values[flag.key] = true
        }
        arguments = []
    }

    /// An empty snapshot: every flag answers its own `defaultValue`.
    ///
    /// Useful in a Release build, where no store is constructed at all, and as a
    /// starting value before the real snapshot has been read.
    public static let empty = DebugFlagSnapshot(values: [:], arguments: [])

    /// Whether the flag is on: a launch argument the snapshot was taken under
    /// forces `true`; otherwise the value read at that moment, or the flag's
    /// `defaultValue` when it was not among the flags read.
    public func isOn(_ flag: DebugFlag) -> Bool {
        if let launchArgument = flag.launchArgument, arguments.contains(launchArgument) {
            return true
        }
        return values[flag.key] ?? flag.defaultValue
    }
}
