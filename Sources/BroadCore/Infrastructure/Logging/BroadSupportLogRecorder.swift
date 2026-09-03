import Foundation

/// In-memory ring buffer typed-событий для вложения `support-log.txt` в письмо
/// в поддержку.
///
/// Recorder хранит те же строки `[TAG] event.name key=value`, что и
/// ``OSLogBroadLogger``, с UTC-временем в начале. По построению в буфер не могут
/// попасть секреты, payload или персональные данные: ``BroadLogEvent`` принимает
/// только закрытые enum, `Bool` и счётчики, а строка собирается единственным
/// внутренним форматтером. Отдельная очистка перед вложением не требуется.
///
/// `log(_:)` не выполняет I/O и держит короткую критическую секцию, поэтому
/// recorder можно передавать вместе с ``OSLogBroadLogger`` через
/// ``CompositeBroadLogger`` во все компоненты платформы. Буфер ограничен
/// `capacity`: при переполнении самые старые записи отбрасываются, а их число
/// доступно через ``droppedEventCount`` и попадает в шапку файла.
public final class BroadSupportLogRecorder: BroadLoggerProtocol, @unchecked Sendable {
    public static let defaultCapacity = 500

    public let capacity: Int

    private let lock = NSLock()
    private let timestampFormatter: ISO8601DateFormatter
    private var buffer: [String?]
    private var startIndex = 0
    private var storedCount = 0
    private var droppedCount = 0

    /// - Parameter capacity: максимальное число хранимых записей; значения меньше 1
    ///   поднимаются до 1, чтобы recorder никогда не терял последнее событие.
    public init(capacity: Int = BroadSupportLogRecorder.defaultCapacity) {
        let normalizedCapacity = max(1, capacity)
        self.capacity = normalizedCapacity
        buffer = Array(repeating: nil, count: normalizedCapacity)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        timestampFormatter = formatter
    }

    /// Число записей, которые сейчас находятся в буфере.
    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    /// Сколько самых старых записей было вытеснено переполнением с момента
    /// создания или последнего ``reset()``.
    public var droppedEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return droppedCount
    }

    public func log(_ event: BroadLogEvent) {
        let line = "\(timestampFormatter.string(from: Date())) \(BroadLogEventFormatter.line(for: event))"
        lock.lock()
        defer { lock.unlock() }
        if storedCount == capacity {
            buffer[startIndex] = line
            startIndex = (startIndex + 1) % capacity
            droppedCount += 1
        } else {
            buffer[(startIndex + storedCount) % capacity] = line
            storedCount += 1
        }
    }

    /// Готовый текст `support-log.txt`: шапка со счётчиками и записи в порядке
    /// поступления, самая старая первой.
    public func makeSupportLog() -> String {
        let generatedAt = timestampFormatter.string(from: Date())
        lock.lock()
        let entries = (0 ..< storedCount).compactMap { offset in
            buffer[(startIndex + offset) % capacity]
        }
        let dropped = droppedCount
        lock.unlock()

        var lines = [
            "BroadCore support log",
            "generated_at=\(generatedAt)",
            "entries=\(entries.count) capacity=\(capacity) dropped=\(dropped)",
            ""
        ]
        lines.append(contentsOf: entries)
        return lines.joined(separator: "\n") + "\n"
    }

    /// UTF-8 представление ``makeSupportLog()`` для
    /// `BroadSupportEmailConfiguration.supportLogData`.
    public func makeSupportLogData() -> Data {
        Data(makeSupportLog().utf8)
    }

    /// Очищает буфер и счётчик вытесненных записей.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer = Array(repeating: nil, count: capacity)
        startIndex = 0
        storedCount = 0
        droppedCount = 0
    }
}
