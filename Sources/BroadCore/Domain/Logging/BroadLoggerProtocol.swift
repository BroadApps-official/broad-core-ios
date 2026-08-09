public protocol BroadLoggerProtocol: Sendable {
    func log(_ event: BroadLogEvent)
}
