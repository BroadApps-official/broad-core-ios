import Foundation

@main
enum BroadCoreLoggingProbe {
    static func main() {
        let recorder = BroadSupportLogRecorder(capacity: 3)
        expect(recorder.capacity == 3, "capacity is kept")
        expect(BroadSupportLogRecorder(capacity: 0).capacity == 1, "capacity below one is raised to one")
        expect(recorder.entryCount == 0, "fresh recorder is empty")

        recorder.log(.bootstrapRunStarted(criticalStepCount: 2, backgroundStepCount: 1))
        recorder.log(.bootstrapStateChanged(.ready))
        expect(recorder.entryCount == 2, "entries are counted")

        let log = recorder.makeSupportLog()
        expect(log.hasPrefix("BroadCore support log\ngenerated_at="), "support log header")
        expect(log.contains("entries=2 capacity=3 dropped=0"), "support log counters")
        expect(
            log.contains("[BOOTSTRAP] bootstrap.run.started critical_steps=2 background_steps=1"),
            "line contains tag, event name and typed fields"
        )
        expect(log.contains("[BOOTSTRAP] bootstrap.state.changed state=ready"), "second line is recorded")
        expect(entryLines(in: log).allSatisfy(isTimestamped), "every entry starts with an ISO8601 UTC timestamp")
        expect(recorder.makeSupportLogData() == Data(log.utf8), "data matches the text representation")

        recorder.log(.cacheReadCompleted(.fresh))
        recorder.log(.workBlocked(capability: .history, reason: .backendContractMissing))
        expect(recorder.entryCount == 3, "buffer never exceeds capacity")
        expect(recorder.droppedEventCount == 1, "overflow is counted")

        let overflowed = entryLines(in: recorder.makeSupportLog())
        expect(overflowed.count == 3, "overflowed log keeps capacity entries")
        expect(!overflowed[0].contains("bootstrap.run.started"), "oldest entry is dropped first")
        expect(overflowed[0].contains("bootstrap.state.changed"), "FIFO order after overflow")
        expect(overflowed[2].contains("[BLOCKED] work.blocked capability=history"), "newest entry is last")

        let sink = RecordingLogger()
        let composite = CompositeBroadLogger(loggers: [sink, recorder])
        composite.log(.verificationPassed(.functional))
        expect(sink.events == [.verificationPassed(.functional)], "composite forwards to every logger")
        expect(recorder.droppedEventCount == 2, "composite reaches the recorder too")

        recorder.reset()
        expect(recorder.entryCount == 0 && recorder.droppedEventCount == 0, "reset clears entries and counters")
        expect(recorder.makeSupportLog().contains("entries=0 capacity=3 dropped=0"), "reset log is empty")

        checkHostEvents()

        CompositeBroadLogger(loggers: []).log(.bootstrapRunJoined)
    }

    /// Declared host codes, counters and flags preserve their meaning in the
    /// formatted support log.
    private static func checkHostEvents() {
        let recorder = BroadSupportLogRecorder(capacity: 8)
        recorder.log(.host(BroadLogHostEvent(
            code: "musicfy.job.failed",
            category: .backend,
            level: .error,
            fields: [
                BroadLogHostField("code", "MODERATION_BLOCKED"),
                BroadLogHostField("attempt", 2),
                BroadLogHostField("retry", false)
            ]
        )))
        let log = recorder.makeSupportLog()
        expect(
            log.contains("[BACKEND] musicfy.job.failed code=MODERATION_BLOCKED attempt=2 retry=false"),
            "host event keeps its category, code and typed fields"
        )

        let normalized = BroadLogHostEvent(
            code: "job status/changed",
            fields: [BroadLogHostField("phase name", "READY NOW")]
        )
        expect(normalized.code == "job-status-changed", "code punctuation is normalized")
        expect(normalized.fields[0].name == "phase-name", "field names are normalized")
        expect(normalized.fields[0].value == "READY-NOW", "symbolic values are normalized")

        let empty = BroadLogHostEvent(code: "")
        expect(empty.code == "host.event", "an empty code falls back to a stable name")
        expect(BroadLogHostField("", "value").name == "field", "an empty field name falls back")

        let many = BroadLogHostEvent(
            code: "probe.fields",
            fields: (0 ..< 20).map { BroadLogHostField("attempt", $0) }
        )
        expect(many.fields.count == BroadLogHostEvent.maximumFieldCount, "field count is capped")
        expect(many.fields.map(\.value) == (0 ..< 8).map(String.init), "field order and duplicate names are preserved")
        let longCode: StaticString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnop"
        let bounded = BroadLogHostEvent(code: longCode, fields: [BroadLogHostField(longCode, longCode)])
        expect(bounded.code.count == BroadLogHostEvent.maximumCodeLength, "event codes are bounded")
        expect(bounded.fields[0].name.count == BroadLogHostEvent.maximumFieldLength, "field names are bounded")
        expect(bounded.fields[0].value.count == BroadLogHostEvent.maximumFieldLength, "symbolic values are bounded")
        expect(BroadLogHostField("enabled", true).value == "true", "true flags are formatted")
        expect(BroadLogHostField("delta", -2).value == "-2", "signed counters are preserved")

        expect(
            BroadLogEvent.host(BroadLogHostEvent(code: "probe.level", level: .warning)).level == .warning,
            "level comes from the host event"
        )
        expect(
            BroadLogEvent.host(BroadLogHostEvent(code: "probe.name")).name == "probe.name",
            "name is the host code"
        )
    }

    private static func entryLines(in log: String) -> [String] {
        log.split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst(3)
            .map(String.init)
    }

    private static func isTimestamped(_ line: String) -> Bool {
        guard let separator = line.firstIndex(of: " ") else { return false }
        let timestamp = String(line[..<separator])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return timestamp.hasSuffix("Z") && formatter.date(from: timestamp) != nil
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ contract: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("Contract violation: \(contract)\n".utf8))
            Foundation.exit(1)
        }
    }
}

private final class RecordingLogger: BroadLoggerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BroadLogEvent] = []

    var events: [BroadLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func log(_ event: BroadLogEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
}
