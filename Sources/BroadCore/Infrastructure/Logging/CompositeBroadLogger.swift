/// Доставляет каждое событие всем вложенным logger-ам в порядке их объявления.
///
/// Composition root создаёт один экземпляр и передаёт его во все компоненты
/// платформы, чтобы событие одновременно попадало в Console через
/// ``OSLogBroadLogger`` и в буфер ``BroadSupportLogRecorder`` для письма в
/// поддержку. Пустой список допустим и ведёт себя как ``NoOpBroadLogger``.
public struct CompositeBroadLogger: BroadLoggerProtocol {
    private let loggers: [any BroadLoggerProtocol]

    public init(loggers: [any BroadLoggerProtocol]) {
        self.loggers = loggers
    }

    public func log(_ event: BroadLogEvent) {
        for logger in loggers {
            logger.log(event)
        }
    }
}
