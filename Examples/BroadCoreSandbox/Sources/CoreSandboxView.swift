import BroadCore
import Foundation
import SwiftUI

struct CoreSandboxView: View {
    @State private var bootstrapState = "idle"
    @State private var isRunning = false

    private let cachePolicy = CachePolicy(timeToLive: 3600)
    private let retryPolicy = RetryPolicy.exponential(
        retryCount: 3,
        initialDelay: 0.25,
        maximumDelay: 1
    )
    private let supportLogRecorder = BroadSupportLogRecorder()
    private let logger: CompositeBroadLogger

    init() {
        logger = CompositeBroadLogger(
            loggers: [
                OSLogBroadLogger(subsystem: Bundle.main.bundleIdentifier ?? "com.broadapps.core-sandbox"),
                supportLogRecorder
            ]
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
                    Text(supportLogRecorder.makeSupportLog())
                        .font(.caption.monospaced())
                }

                Section("ATT boundary") {
                    Text("Core exposes the adapter. A visible onboarding flow decides when to request permission.")
                }
            }
            .navigationTitle("BroadCore")
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
