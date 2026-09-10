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

    /// The host case carries app-owned codes into the same log, and sanitizes
    /// them so a support letter cannot leak a URL, a receipt or a stack trace.
    private static func checkHostEvents() {
        let recorder = BroadSupportLogRecorder(capacity: 8)
        recorder.log(.host(BroadLogHostEvent(
            code: "musicfy.job.failed",
            category: .backend,
            level: .error,
            fields: [BroadLogHostField("code", "MODERATION_BLOCKED"), BroadLogHostField("attempt", 2)]
        )))
        let log = recorder.makeSupportLog()
        expect(
            log.contains("[BACKEND] musicfy.job.failed code=MODERATION_BLOCKED attempt=2"),
            "host event keeps its category, code and typed fields"
        )

        let leaking = BroadLogHostEvent(
            code: "job failed at https://example.com/x?token=abc",
            fields: [BroadLogHostField("message", "Bearer abc.def/ghi")]
        )
        expect(!leaking.code.contains("/") && !leaking.code.contains("?"), "code drops URL punctuation")
        expect(!leaking.code.contains(" "), "code drops whitespace")
        expect(!leaking.fields[0].value.contains("/"), "field value drops path separators")
        expect(leaking.fields[0].value.count <= BroadLogHostEvent.maximumFieldLength, "field value is capped")

        let empty = BroadLogHostEvent(code: "")
        expect(empty.code == "host.event", "an empty code falls back to a stable name")
        expect(BroadLogHostField("", "value").name == "field", "an empty field name falls back")

        let many = BroadLogHostEvent(
            code: "probe.fields",
            fields: (0 ..< 20).map { BroadLogHostField("f\($0)", $0) }
        )
        expect(many.fields.count == BroadLogHostEvent.maximumFieldCount, "field count is capped")

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
