import BroadCore
import Foundation
import SwiftUI

struct CoreSandboxView: View {
    @State private var bootstrapState = "idle"
    @State private var isRunning = false
    /// Redraws the support log after a host event is written into the recorder.
    @State private var loggedHostEvents = 0
    @State private var accountIdentifier = "not resolved"

    private let cachePolicy = CachePolicy(timeToLive: 3600)
    private let retryPolicy = RetryPolicy.exponential(
        retryCount: 3,
        initialDelay: 0.25,
        maximumDelay: 1
    )
    private let supportLogRecorder = BroadSupportLogRecorder()
    private let logger: CompositeBroadLogger
    private let accountIdentifierStore: KeychainAccountIdentifierStore

    init() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.broadapps.core-sandbox"
        logger = CompositeBroadLogger(
            loggers: [
                OSLogBroadLogger(subsystem: bundleIdentifier),
                supportLogRecorder
            ]
        )
        accountIdentifierStore = KeychainAccountIdentifierStore(
            configuration: KeychainAccountIdentifierConfiguration(service: "\(bundleIdentifier).account"),
            failureError: AppError(
                kind: .unavailable,
                userMessage: "Keychain is not available yet.",
                diagnosticCode: "sandbox.account-identifier.unavailable",
                isRetryable: true
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bootstrap") {
                    LabeledContent("State", value: bootstrapState)
                    Button(isRunning ? "Running…" : "Run safe bootstrap") {
                        runBootstrap()
                    }
                    .disabled(isRunning)
                }

                Section("Cache") {
                    LabeledContent("TTL", value: "\(Int(cachePolicy.timeToLive)) seconds")
                    LabeledContent("Schema mismatch", value: "preserve")
                    LabeledContent("Corruption", value: "remove")
                }

                Section("Retry and timeout") {
                    LabeledContent("Retries", value: "\(retryPolicy.delays.count)")
                    LabeledContent("Step timeout", value: "2 seconds")
                }

                Section("Typed network failure") {
                    LabeledContent(
                        "Offline",
                        value: String(describing: NetworkFailureClassifier.classify(URLError(.notConnectedToInternet)))
                    )
                    LabeledContent("Raw URL/error", value: "not logged")
                }

                Section("Support log") {
                    LabeledContent("Recorded events", value: "\(supportLogRecorder.entryCount)")
                    Button("Log a host event") {
                        logger.log(.host(BroadLogHostEvent(
                            code: "sandbox.job.failed",
                            category: .backend,
                            level: .error,
                            fields: [
                                BroadLogHostField("code", "MODERATION_BLOCKED"),
                                BroadLogHostField("attempt", 2),
                                BroadLogHostField("retry", false)
                            ]
                        )))
                        loggedHostEvents += 1
                    }
                    Text(supportLogRecorder.makeSupportLog())
                        .font(.caption.monospaced())
                        .id(loggedHostEvents)
                }

                Section("Account identifier") {
                    LabeledContent("Resolution", value: accountIdentifier)
                    Button("Resolve") {
                        resolveAccountIdentifier()
                    }
                    Text("An unsigned build has no Keychain entitlement, so resolution fails. Use a signed build.")
                }

                Section("ATT boundary") {
                    Text("Core exposes the adapter. A visible onboarding flow decides when to request permission.")
                }
            }
            .navigationTitle("BroadCore")
        }
    }

    private func resolveAccountIdentifier() {
        Task {
            switch await accountIdentifierStore.resolve() {
            case let .resolved(identifier, source):
                accountIdentifier = "\(source.rawValue) · \(identifier.prefix(8))…"
            case let .failed(error):
                accountIdentifier = error.diagnosticCode
            }
        }
    }

    private func runBootstrap() {
        isRunning = true
        bootstrapState = "starting"
        Task {
            let coordinator = AppBootstrapCoordinator(
                steps: [
                    BootstrapStep(
                        id: .init(rawValue: "configuration"),
                        name: "Load safe fixture",
                        criticality: .critical,
                        timeoutPolicy: .seconds(2),
                        retryPolicy: .fixed(retryCount: 1, delay: 0.1)
                    ) {
                        .completed
                    }
                ],
                logger: logger
            )
            let state = await coordinator()
            bootstrapState = String(describing: state)
            isRunning = false
        }
    }
}
