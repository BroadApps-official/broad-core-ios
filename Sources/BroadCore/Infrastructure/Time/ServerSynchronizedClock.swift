import Foundation

/// Current time derived from the host's own backend answers instead of the device
/// clock.
///
/// Anything paid that depends on time — a campaign deadline, a countdown, a quiet
/// period between offers — must not run on the device clock: the user can move it
/// forward to end a window early, or back to start a new one. Every backend answer
/// carries a `Date` header, so the host learns server time from calls it already
/// makes: it feeds each server date to `record(_:)` and the gap to the device
/// clock is kept and applied to every reading.
///
/// The gap is persisted, because a window outlives the process that opened it: a
/// relaunch two hours in must still see two hours. Readings never move backwards,
/// so winding the device clock back buys nothing. A recorded server date is the
/// authority and may move the mark in either direction — only the device cannot.
///
/// Until the first server date arrives, readings are ``ServerTimeReading/unverified(_:)``:
/// the value is the device clock, and callers that decide money are expected to
/// refuse it rather than work quietly on it.
public actor ServerSynchronizedClock: ServerTimeProviderProtocol {
    private struct Persisted: Codable, Equatable {
        var offset: TimeInterval?
        var highWater: TimeInterval?
    }

    public static let defaultStorageKey = "broadcore.server-clock.v1"

    /// How far a reading must advance before the new mark is written. Persisting
    /// every read would mean a store write per frame of a countdown.
    private static let highWaterPersistStep: TimeInterval = 60

    private let store: any KeyValueStoreProtocol
    private let storageKey: String
    private let deviceNow: @Sendable () -> Date

    private var loaded = false
    private var loadTask: Task<Void, Never>?
    private var offset: TimeInterval?
    private var highWater = Date.distantPast
    private var persistedHighWater = Date.distantPast

    public init(
        store: any KeyValueStoreProtocol,
        storageKey: String = ServerSynchronizedClock.defaultStorageKey,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(!storageKey.isEmpty, "Server clock storage key must not be empty")
        self.store = store
        self.storageKey = storageKey
        deviceNow = now
    }

    /// Records a trusted server date, normally the `Date` header of a backend
    /// answer. Non-finite dates are ignored.
    public func record(_ date: Date) async {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            return
        }
        await ensureLoaded()

        offset = date.timeIntervalSince(deviceNow())
        // The server is the authority. When it reports a time earlier than the
        // mark this device had reached, the mark follows it down rather than
        // freezing the clock at a value the server does not agree with.
        if date < highWater {
            highWater = date
            persistedHighWater = date
        }
        await persist()
    }

    /// Records the `Date` header of an HTTP answer. Returns whether a date was
    /// found and parsed, so a host can tell "no header" from "recorded".
    @discardableResult
    public func record(_ response: HTTPURLResponse) async -> Bool {
        guard let date = HTTPServerDate.date(from: response) else {
            return false
        }
        await record(date)
        return true
    }

    /// Whether a server date has been recorded, in this process or a previous one.
    public func isSynchronized() async -> Bool {
        await ensureLoaded()
        return offset != nil
    }

    public func reading() async -> ServerTimeReading {
        await ensureLoaded()

        // The mark records trusted time only. An unverified reading is handed
        // over as the device reports it, so it cannot poison the mark that
        // synchronized readings are held against.
        guard let offset else {
            return .unverified(deviceNow())
        }

        let candidate = deviceNow().addingTimeInterval(offset)
        return await .synchronized(advanceMark(to: candidate))
    }

    /// Forgets the recorded offset and the mark. Intended for debug state resets;
    /// a host does not call this in a normal flow.
    public func reset() async {
        await ensureLoaded()

        offset = nil
        highWater = .distantPast
        persistedHighWater = .distantPast
        try? await store.remove(storageKey)
    }

    private func advanceMark(to candidate: Date) async -> Date {
        guard candidate > highWater else {
            // The device clock moved back, or has not caught up with the mark.
            return highWater
        }

        highWater = candidate
        if candidate.timeIntervalSince(persistedHighWater) >= Self.highWaterPersistStep {
            persistedHighWater = candidate
            await persist()
        }
        return candidate
    }

    /// Reads the persisted state once, and makes every other caller wait for that
    /// one read.
    ///
    /// The flag alone would not be enough: the read suspends, so a second caller
    /// arriving while the first is still waiting would sail past a flag set up
    /// front and answer `unverified` with an offset that is about to arrive. On a
    /// warm relaunch that is a refused offer for a user whose time is known.
    private func ensureLoaded() async {
        if loaded {
            return
        }
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [self] in
            await load()
        }
        loadTask = task
        await task.value
    }

    private func load() async {
        defer {
            loaded = true
            loadTask = nil
        }

        guard case let .data(data) = await (try? store.read(storageKey)) ?? .missing,
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data)
        else {
            return
        }
        offset = persisted.offset
        if let mark = persisted.highWater {
            let date = Date(timeIntervalSinceReferenceDate: mark)
            highWater = date
            persistedHighWater = date
        }
    }

    private func persist() async {
        let persisted = Persisted(
            offset: offset,
            highWater: highWater == .distantPast
                ? nil
                : highWater.timeIntervalSinceReferenceDate
        )
        guard let data = try? JSONEncoder().encode(persisted) else {
            return
        }
        try? await store.write(data, forKey: storageKey)
    }
}

/// Reads the `Date` header of an HTTP answer into a `Date` a host can feed to
/// `ServerSynchronizedClock.record(_:)`.
public enum HTTPServerDate {
    /// RFC 1123 first, because that is what a current server sends. The two
    /// obsolete formats are still legal HTTP and still come out of old proxies;
    /// failing to read one would leave the clock unsynchronized and, under the
    /// default policy, silently switch a campaign off.
    private static let formatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEEE, dd-MMM-yy HH:mm:ss zzz",
        "EEE MMM d HH:mm:ss yyyy"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = format
        return formatter
    }

    public static func date(from response: HTTPURLResponse) -> Date? {
        guard let header = response.value(forHTTPHeaderField: "Date") else {
            return nil
        }
        return date(fromHeader: header)
    }

    public static func date(fromHeader header: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: header) {
                return date
            }
        }
        return nil
    }
}
