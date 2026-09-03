import Foundation

/// In-memory stand-in for the host's store, so the probe exercises persistence
/// without touching the file system.
private actor MemoryStore: KeyValueStoreProtocol {
    private var values: [String: Data] = [:]

    func read(_ key: String) async throws -> KeyValueStoreEntry {
        values[key].map(KeyValueStoreEntry.data) ?? .missing
    }

    func write(_ data: Data, forKey key: String) async throws {
        values[key] = data
    }

    func write(
        _ data: Data,
        forKey key: String,
        ifMatching _: KeyValueStoreEntry
    ) async throws -> Bool {
        values[key] = data
        return true
    }

    func remove(_ key: String) async throws {
        values.removeValue(forKey: key)
    }

    func remove(_ key: String, ifMatching _: KeyValueStoreEntry) async throws -> Bool {
        values.removeValue(forKey: key) != nil
    }
}

/// A device clock the probe can move, the way a user can.
private final class MovableDeviceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Date) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func advance(by interval: TimeInterval) {
        set(now.addingTimeInterval(interval))
    }
}

@main
enum BroadCoreServerClockProbe {
    private static let deviceOrigin = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let serverOrigin = Date(timeIntervalSinceReferenceDate: 800_003_600)

    static func main() async {
        await checkUnverifiedBeforeAnyServerAnswer()
        await checkServerAnswerSetsTheOffset()
        await checkDeviceClockMovedForwardIsFollowed()
        await checkDeviceClockMovedBackIsRefused()
        await checkOffsetSurvivesARelaunch()
        await checkServerMayMoveTheMarkBack()
        await checkNonFiniteDatesAreIgnored()
        await checkConcurrentFirstReadSeesThePersistedOffset()
        checkHTTPDateHeaderIsParsed()
        print(
            "PASS: server clock is unverified until the backend answers, applies "
                + "and persists the offset, and never moves backwards on the device"
        )
    }

    private static func checkUnverifiedBeforeAnyServerAnswer() async {
        let device = MovableDeviceClock(deviceOrigin)
        let clock = makeClock(store: MemoryStore(), device: device)

        let reading = await clock.reading()
        guard case let .unverified(date) = reading, date == deviceOrigin else {
            fatalError("Before any server answer the reading must be the unverified device clock")
        }
        guard await clock.isSynchronized() == false else {
            fatalError("A clock that never heard from the backend is not synchronized")
        }
    }

    private static func checkServerAnswerSetsTheOffset() async {
        let device = MovableDeviceClock(deviceOrigin)
        let clock = makeClock(store: MemoryStore(), device: device)

        await clock.record(serverOrigin)
        guard case let .synchronized(date) = await clock.reading(), date == serverOrigin else {
            fatalError("A recorded server date must become the current reading")
        }
        guard await clock.isSynchronized() else {
            fatalError("A clock that heard from the backend is synchronized")
        }
    }

    private static func checkDeviceClockMovedForwardIsFollowed() async {
        let device = MovableDeviceClock(deviceOrigin)
        let clock = makeClock(store: MemoryStore(), device: device)
        await clock.record(serverOrigin)

        device.advance(by: 60)
        guard case let .synchronized(date) = await clock.reading(),
              date == serverOrigin.addingTimeInterval(60)
        else {
            fatalError("Time must keep running between server answers")
        }
    }

    private static func checkDeviceClockMovedBackIsRefused() async {
        let device = MovableDeviceClock(deviceOrigin)
        let clock = makeClock(store: MemoryStore(), device: device)
        await clock.record(serverOrigin)

        device.advance(by: 3600)
        guard case let .synchronized(mark) = await clock.reading() else {
            fatalError("Expected a synchronized reading")
        }

        // The user winds the device back a day to extend a paid window.
        device.advance(by: -24 * 3600)
        guard case let .synchronized(afterRewind) = await clock.reading(),
              afterRewind == mark
        else {
            fatalError("Winding the device clock back must not move time backwards")
        }
    }

    private static func checkOffsetSurvivesARelaunch() async {
        let store = MemoryStore()
        let device = MovableDeviceClock(deviceOrigin)
        let first = makeClock(store: store, device: device)
        await first.record(serverOrigin)
        device.advance(by: 7200)
        _ = await first.reading()

        // A second instance over the same store is what the next launch sees.
        let relaunched = makeClock(store: store, device: device)
        guard await relaunched.isSynchronized() else {
            fatalError("A relaunch must not forget that the backend has answered")
        }
        guard case let .synchronized(date) = await relaunched.reading(),
              date == serverOrigin.addingTimeInterval(7200)
        else {
            fatalError("A relaunch must resume from the same server time, not from the device")
        }

        device.advance(by: -7200)
        guard case let .synchronized(afterRewind) = await relaunched.reading(),
              afterRewind == serverOrigin.addingTimeInterval(7200)
        else {
            fatalError("The persisted mark must hold across a relaunch too")
        }
    }

    /// A warm relaunch with several features asking at once must not answer one
    /// of them `unverified` while the persisted offset is still being read.
    private static func checkConcurrentFirstReadSeesThePersistedOffset() async {
        let store = MemoryStore()
        let device = MovableDeviceClock(deviceOrigin)
        let first = makeClock(store: store, device: device)
        await first.record(serverOrigin)

        let relaunched = makeClock(store: store, device: device)
        async let a = relaunched.reading()
        async let b = relaunched.reading()
        async let synchronized = relaunched.isSynchronized()
        let readings = await [a, b]

        guard await synchronized else {
            fatalError("A concurrent first call must not report an unsynchronized clock")
        }
        for reading in readings {
            guard case .synchronized = reading else {
                fatalError("Every concurrent first reading must see the persisted offset")
            }
        }
    }

    private static func checkServerMayMoveTheMarkBack() async {
        let device = MovableDeviceClock(deviceOrigin)
        let clock = makeClock(store: MemoryStore(), device: device)
        await clock.record(serverOrigin)
        device.advance(by: 3600)
        _ = await clock.reading()

        // The backend is the authority: when it reports an earlier time than the
        // mark this device reached, the mark follows it rather than freezing.
        let corrected = serverOrigin.addingTimeInterval(600)
        await clock.record(corrected)
        guard case let .synchronized(date) = await clock.reading(), date == corrected else {
            fatalError("A server correction must be applied even when it moves time back")
        }
    }

    private static func checkNonFiniteDatesAreIgnored() async {
        let device = MovableDeviceClock(deviceOrigin)
        let clock = makeClock(store: MemoryStore(), device: device)

        await clock.record(Date(timeIntervalSinceReferenceDate: .infinity))
        guard await clock.isSynchronized() == false else {
            fatalError("A non-finite date must not count as a server answer")
        }
    }

    private static func checkHTTPDateHeaderIsParsed() {
        guard let parsed = HTTPServerDate.date(fromHeader: "Wed, 03 Sep 2026 15:25:51 GMT") else {
            fatalError("An RFC 1123 Date header must be understood")
        }
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 3
        components.hour = 15
        components.minute = 25
        components.second = 51
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT") ?? .gmt
        guard parsed == calendar.date(from: components) else {
            fatalError("A Date header must be read as GMT")
        }
        guard HTTPServerDate.date(fromHeader: "not a date") == nil else {
            fatalError("An unparsable Date header must be refused")
        }
    }

    private static func makeClock(
        store: some KeyValueStoreProtocol,
        device: MovableDeviceClock
    ) -> ServerSynchronizedClock {
        ServerSynchronizedClock(
            store: store,
            storageKey: "probe.server-clock",
            now: { device.now }
        )
    }
}
