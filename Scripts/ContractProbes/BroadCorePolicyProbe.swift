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
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ contract: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("Contract violation: \(contract)\n".utf8))
            Foundation.exit(1)
        }
    }
}
