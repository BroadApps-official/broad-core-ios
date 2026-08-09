public struct NoOpBroadLogger: BroadLoggerProtocol {
    public init() {}

    public func log(_: BroadLogEvent) {}
}
