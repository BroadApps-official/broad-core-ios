import Foundation

@main
enum BroadCorePolicyProbe {
    static func main() {
        let fixed = RetryPolicy.fixed(retryCount: 2, delay: 0.25)
        expect(fixed.delays == [.milliseconds(250), .milliseconds(250)], "fixed retry sequence")

        let exponential = RetryPolicy.exponential(
            retryCount: 4,
            initialDelay: 0.1,
            multiplier: 3,
            maximumDelay: 0.5
        )
        expect(
            exponential.delays == [.milliseconds(100), .milliseconds(300), .milliseconds(500), .milliseconds(500)],
            "bounded exponential retry sequence"
        )

        expect(TimeoutPolicy.seconds(1.25).limit == .milliseconds(1250), "timeout conversion")

        let cache = CachePolicy(timeToLive: 60)
        expect(cache.timeToLive == 60, "cache TTL")
        expect(cache.corruptedEntryAction == .remove, "corrupted cache removal")
        expect(cache.schemaMismatchAction == .preserve, "schema mismatch preservation")
        expect(cache.versionMismatchAction == .remove, "version mismatch removal")

        expect(
            NetworkFailureClassifier.classify(URLError(.notConnectedToInternet)) == .offline,
            "offline classification"
        )
        expect(
            NetworkFailureClassifier.classify(URLError(.timedOut)) == .timedOut,
            "timeout classification"
        )
        expect(
            NetworkFailureClassifier.classify(CancellationError()) == .cancelled,
            "cancellation classification"
        )

        expect(
            NetworkFailureClassifier.classify(URLError(.dnsLookupFailed)) == .offline,
            "a lost DNS lookup reads as offline"
        )
        expect(
            NetworkFailureClassifier.classify(URLError(.internationalRoamingOff)) == .offline,
            "roaming switched off reads as offline"
        )

        let offline = AppError.transportFailure(
            URLError(.notConnectedToInternet),
            diagnosticPrefix: "probe.backend"
        )
        expect(offline.kind == .offline, "offline failure keeps the offline kind")
        expect(offline.isRetryable, "offline failure is worth retrying")
        expect(offline.diagnosticCode == "probe.backend.offline", "diagnostic code carries the prefix")
        expect(
            offline.userMessage == TransportErrorMessages.englishDefault.offline,
            "default copy is used when the host supplies none"
        )

        let timedOut = AppError.transportFailure(
            URLError(.timedOut),
            diagnosticPrefix: "probe.backend"
        )
        expect(timedOut.kind == .timeout, "timeout failure keeps the timeout kind")
        expect(timedOut.isRetryable, "timeout failure is worth retrying")

        let cancelled = AppError.transportFailure(
            CancellationError(),
            diagnosticPrefix: "probe.backend"
        )
        expect(!cancelled.isRetryable, "a cancelled request is not retried on its own")
        expect(cancelled.diagnosticCode == "probe.backend.cancelled", "cancellation has its own code")

        let hostCopy = TransportErrorMessages(
            offline: "Нет соединения",
            timedOut: "Слишком долго",
            cancelled: "Отменено",
            other: "Что-то пошло не так"
        )
        expect(
            AppError.transportFailure(
                URLError(.badServerResponse),
                messages: hostCopy,
                diagnosticPrefix: "probe.backend"
            ).userMessage == hostCopy.other,
            "host copy replaces the default"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ contract: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("Contract violation: \(contract)\n".utf8))
            Foundation.exit(1)
        }
    }
}
