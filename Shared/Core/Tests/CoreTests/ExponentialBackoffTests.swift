import Testing
import Foundation
@testable import Core

@Suite("ExponentialBackoff Tests")
struct ExponentialBackoffTests {

    @Test("Default configuration has correct values")
    func defaultConfiguration() {
        let backoff = ExponentialBackoff.default

        #expect(backoff.initialWaitTime == 0.5)
        #expect(backoff.maximumWaitTime == 10.0)
        #expect(backoff.maximumAttempts == 10)
        #expect(backoff.numberOfAttempts == 0)
        #expect(backoff.totalWaitTime == 0.0)
        #expect(!backoff.isExhausted)
    }

    @Test("First attempt returns zero wait time")
    func firstAttemptReturnsZero() {
        var backoff = ExponentialBackoff.default

        let waitTime = backoff.nextWaitTime()

        #expect(waitTime == 0.0)
        #expect(backoff.numberOfAttempts == 1)
    }

    @Test("Returns nil when max attempts exhausted")
    func returnsNilWhenExhausted() {
        var backoff = ExponentialBackoff(initialWaitTime: 0.1, maximumWaitTime: 1.0, maximumAttempts: 3)

        #expect(backoff.nextWaitTime() != nil) // 1
        #expect(backoff.nextWaitTime() != nil) // 2
        #expect(backoff.nextWaitTime() != nil) // 3
        #expect(backoff.isExhausted)
        #expect(backoff.nextWaitTime() == nil) // exhausted
    }

    @Test("Wait times increase exponentially")
    func waitTimesIncreaseExponentially() {
        var backoff = ExponentialBackoff(initialWaitTime: 1.0, maximumWaitTime: 100.0, maximumAttempts: 10)

        // First attempt is 0
        let first = backoff.nextWaitTime()!
        #expect(first == 0.0)

        // Second attempt: 1.0 * 2^0 = 1.0 (plus random 0-1)
        let second = backoff.nextWaitTime()!
        #expect(second >= 1.0 && second < 2.0)

        // Third attempt: 1.0 * 2^1 = 2.0 (plus random 0-1)
        let third = backoff.nextWaitTime()!
        #expect(third >= 2.0 && third < 3.0)

        // Fourth attempt: 1.0 * 2^2 = 4.0 (plus random 0-1)
        let fourth = backoff.nextWaitTime()!
        #expect(fourth >= 4.0 && fourth < 5.0)
    }

    @Test("Wait time is capped at maximum")
    func waitTimeIsCapped() {
        var backoff = ExponentialBackoff(initialWaitTime: 1.0, maximumWaitTime: 5.0, maximumAttempts: 10)

        // Skip to later attempts
        _ = backoff.nextWaitTime() // 0
        _ = backoff.nextWaitTime() // 1
        _ = backoff.nextWaitTime() // 2
        _ = backoff.nextWaitTime() // 4

        // Fifth attempt would be 8.0 but capped at 5.0
        let capped = backoff.nextWaitTime()!
        #expect(capped <= 5.0)
    }

    @Test("Reset clears attempts and total wait time")
    func resetClearsState() {
        var backoff = ExponentialBackoff.default

        _ = backoff.nextWaitTime()
        _ = backoff.nextWaitTime()
        _ = backoff.nextWaitTime()

        #expect(backoff.numberOfAttempts > 0)
        #expect(backoff.totalWaitTime > 0)

        backoff.reset()

        #expect(backoff.numberOfAttempts == 0)
        #expect(backoff.totalWaitTime == 0.0)
        #expect(!backoff.isExhausted)
    }

    @Test("Total wait time accumulates correctly")
    func totalWaitTimeAccumulates() {
        var backoff = ExponentialBackoff(initialWaitTime: 1.0, maximumWaitTime: 100.0, maximumAttempts: 10)

        let first = backoff.nextWaitTime() ?? 0  // 0
        let second = backoff.nextWaitTime() ?? 0 // ~1
        let third = backoff.nextWaitTime() ?? 0  // ~2

        // Total should be sum of all wait times (first is 0, doesn't add to total)
        let expectedMinimum = second + third - first
        #expect(backoff.totalWaitTime >= expectedMinimum - 0.1)
    }

    @Test("Custom configuration is respected")
    func customConfiguration() {
        let backoff = ExponentialBackoff(initialWaitTime: 2.0, maximumWaitTime: 30.0, maximumAttempts: 5)

        #expect(backoff.initialWaitTime == 2.0)
        #expect(backoff.maximumWaitTime == 30.0)
        #expect(backoff.maximumAttempts == 5)
    }

    @Test("TimeInterval nanoseconds conversion")
    func nanosecondConversion() {
        let interval: TimeInterval = 1.5

        #expect(interval.nanoseconds == 1_500_000_000)
    }

    @Test("Description format is correct")
    func descriptionFormat() {
        var backoff = ExponentialBackoff(initialWaitTime: 1.0, maximumWaitTime: 10.0, maximumAttempts: 10)

        _ = backoff.nextWaitTime()
        _ = backoff.nextWaitTime()

        let description = backoff.description
        #expect(description.contains("attempts:"))
        #expect(description.contains("totalWaitTime"))
    }
}
