import OSLog

public struct OSLogBroadLogger: BroadLoggerProtocol {
    private let bootstrapLogger: Logger
    private let cacheLogger: Logger
    private let networkingLogger: Logger
    private let monetizationLogger: Logger
    private let paywallLogger: Logger
    private let purchaseLogger: Logger
    private let ruBillingLogger: Logger
    private let experimentsLogger: Logger
    private let inputLogger: Logger
    private let backendLogger: Logger
    private let flowLogger: Logger
    private let tokensLogger: Logger
    private let analyticsLogger: Logger
    private let uiLogger: Logger
    private let blockedLogger: Logger
    private let passLogger: Logger

    /// Compile-time subsystem literal. Prefer ``init(subsystem:)-(String)`` to set
    /// the subsystem from `Bundle.main.bundleIdentifier` at runtime instead of
    /// duplicating the bundle id as a literal.
    public init(subsystem: StaticString) {
        self.init(subsystem: subsystem.description)
    }

    /// Runtime subsystem, so a host can pass `Bundle.main.bundleIdentifier`
    /// directly rather than repeating it as a compile-time literal.
    public init(subsystem: String) {
        precondition(!subsystem.isEmpty, "Logging subsystem must not be empty")
        precondition(subsystem.utf8.count <= 255, "Logging subsystem must not exceed 255 UTF-8 bytes")
        bootstrapLogger = Logger(subsystem: subsystem, category: BroadLogCategory.bootstrap.rawValue)
        cacheLogger = Logger(subsystem: subsystem, category: BroadLogCategory.cache.rawValue)
        networkingLogger = Logger(subsystem: subsystem, category: BroadLogCategory.networking.rawValue)
        monetizationLogger = Logger(subsystem: subsystem, category: BroadLogCategory.monetization.rawValue)
        paywallLogger = Logger(subsystem: subsystem, category: BroadLogCategory.paywall.rawValue)
        purchaseLogger = Logger(subsystem: subsystem, category: BroadLogCategory.purchase.rawValue)
        ruBillingLogger = Logger(subsystem: subsystem, category: BroadLogCategory.ruBilling.rawValue)
        experimentsLogger = Logger(subsystem: subsystem, category: BroadLogCategory.experiments.rawValue)
        inputLogger = Logger(subsystem: subsystem, category: BroadLogCategory.input.rawValue)
        backendLogger = Logger(subsystem: subsystem, category: BroadLogCategory.backend.rawValue)
        flowLogger = Logger(subsystem: subsystem, category: BroadLogCategory.flow.rawValue)
        tokensLogger = Logger(subsystem: subsystem, category: BroadLogCategory.tokens.rawValue)
        analyticsLogger = Logger(subsystem: subsystem, category: BroadLogCategory.analytics.rawValue)
        uiLogger = Logger(
            subsystem: subsystem,
            category: BroadLogCategory.userInterface.rawValue
        )
        blockedLogger = Logger(subsystem: subsystem, category: BroadLogCategory.blocked.rawValue)
        passLogger = Logger(subsystem: subsystem, category: BroadLogCategory.pass.rawValue)
    }

    public func log(_ event: BroadLogEvent) {
        let logger = logger(for: event.category)
        let message = BroadLogEventFormatter.line(for: event)

        switch event.level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }
}

private extension OSLogBroadLogger {
    private func logger(for category: BroadLogCategory) -> Logger {
        switch category {
        case .input,
             .backend,
             .flow,
             .tokens,
             .analytics,
             .userInterface,
             .blocked,
             .pass:
            developmentLogger(for: category)
        default:
            platformLogger(for: category)
        }
    }

    private func platformLogger(for category: BroadLogCategory) -> Logger {
        switch category {
        case .bootstrap:
            bootstrapLogger
        case .cache:
            cacheLogger
        case .networking:
            networkingLogger
        case .monetization:
            monetizationLogger
        case .paywall:
            paywallLogger
        case .purchase:
            purchaseLogger
        case .ruBilling:
            ruBillingLogger
        case .experiments:
            experimentsLogger
        default:
            developmentLogger(for: category)
        }
    }

    private func developmentLogger(for category: BroadLogCategory) -> Logger {
        switch category {
        case .input:
            inputLogger
        case .backend:
            backendLogger
        case .flow:
            flowLogger
        case .tokens:
            tokensLogger
        case .analytics:
            analyticsLogger
        case .userInterface:
            uiLogger
        case .blocked:
            blockedLogger
        case .pass:
            passLogger
        default:
            platformLogger(for: category)
        }
    }
}
