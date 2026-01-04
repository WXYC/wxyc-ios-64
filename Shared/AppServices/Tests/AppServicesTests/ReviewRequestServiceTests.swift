import Testing
import Foundation
@testable import AppServices

// MARK: - Mock UserDefaults

@MainActor
final class MockUserDefaults: ReviewRequestStorage, Sendable {
    private var storage: [String: Any] = [:]

    func integer(forKey key: String) -> Int {
        storage[key] as? Int ?? 0
    }

    func set(_ value: Int, forKey key: String) {
        storage[key] = value
    }

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func set(_ value: String?, forKey key: String) {
        storage[key] = value
    }
}

// MARK: - Tests

@MainActor
@Suite("ReviewRequestService Tests")
struct ReviewRequestServiceTests {

    // MARK: - Action Recording Tests

    @Test("recordPlaybackStarted increments action count")
    func recordPlaybackStartedIncrementsCount() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // When
        service.recordPlaybackStarted()

        // Then
        #expect(mockDefaults.integer(forKey: "reviewRequest.actionCount") == 1)
    }

    @Test("recordRequestSent increments action count")
    func recordRequestSentIncrementsCount() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // When
        service.recordRequestSent()

        // Then
        #expect(mockDefaults.integer(forKey: "reviewRequest.actionCount") == 1)
    }

    @Test("recordSongAddedToLibrary increments action count")
    func recordSongAddedToLibraryIncrementsCount() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // When
        service.recordSongAddedToLibrary()

        // Then
        #expect(mockDefaults.integer(forKey: "reviewRequest.actionCount") == 1)
    }

    @Test("Mixed action types all increment count")
    func mixedActionsIncrementCount() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // When
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()

        // Then
        #expect(mockDefaults.integer(forKey: "reviewRequest.actionCount") == 3)
    }

    // MARK: - Review Trigger Tests

    @Test("shouldRequestReview becomes true at threshold")
    func shouldRequestReviewAtThreshold() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // When - perform 2 actions (below threshold)
        service.recordPlaybackStarted()
        service.recordRequestSent()

        // Then - not yet triggered
        #expect(service.shouldRequestReview == false)

        // When - perform 3rd action (at threshold)
        service.recordSongAddedToLibrary()

        // Then - should trigger
        #expect(service.shouldRequestReview == true)
    }

    @Test("shouldRequestReview stays false if already requested for version")
    func shouldNotRequestIfAlreadyRequested() async {
        // Given
        let mockDefaults = MockUserDefaults()
        mockDefaults.set("1.0", forKey: "reviewRequest.lastRequestedVersion")
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // When - perform threshold actions
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()

        // Then - should not trigger because already requested for this version
        #expect(service.shouldRequestReview == false)
    }

    @Test("Version flag reset allows new review")
    func versionResetAllowsNewReview() async {
        // Given - already requested for version 1.0
        let mockDefaults = MockUserDefaults()
        mockDefaults.set("1.0", forKey: "reviewRequest.lastRequestedVersion")

        // Create service with higher minimum version
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "2.0"
        )

        // When - perform threshold actions
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()

        // Then - should trigger because minimum version is higher than last requested
        #expect(service.shouldRequestReview == true)
    }

    @Test("didRequestReview resets state and stores version")
    func didRequestReviewResetsState() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // Trigger review
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()
        #expect(service.shouldRequestReview == true)

        // When
        service.didRequestReview()

        // Then
        #expect(service.shouldRequestReview == false)
        #expect(mockDefaults.integer(forKey: "reviewRequest.actionCount") == 0)
        #expect(mockDefaults.string(forKey: "reviewRequest.lastRequestedVersion") == "1.0")
    }

    @Test("Actions after review do not trigger again for same version")
    func actionsAfterReviewDoNotRetrigger() async {
        // Given
        let mockDefaults = MockUserDefaults()
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.0"
        )

        // First review cycle
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()
        service.didRequestReview()

        // When - perform more actions
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()

        // Then - should not trigger again
        #expect(service.shouldRequestReview == false)
    }

    // MARK: - Version Comparison Tests

    @Test("Version comparison handles semantic versions correctly")
    func versionComparisonSemantic() async {
        // Given - already requested for version 1.9
        let mockDefaults = MockUserDefaults()
        mockDefaults.set("1.9", forKey: "reviewRequest.lastRequestedVersion")

        // Create service with version 1.10 (should be greater than 1.9)
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.10"
        )

        // When - perform threshold actions
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()

        // Then - should trigger because 1.10 > 1.9
        #expect(service.shouldRequestReview == true)
    }

    @Test("No review requested when minimum version is lower")
    func noReviewWhenMinimumVersionLower() async {
        // Given - already requested for version 2.0
        let mockDefaults = MockUserDefaults()
        mockDefaults.set("2.0", forKey: "reviewRequest.lastRequestedVersion")

        // Create service with lower minimum version
        let service = ReviewRequestService(
            userDefaults: mockDefaults,
            minimumVersionForReview: "1.5"
        )

        // When - perform threshold actions
        service.recordPlaybackStarted()
        service.recordRequestSent()
        service.recordSongAddedToLibrary()

        // Then - should not trigger because minimum version < last requested
        #expect(service.shouldRequestReview == false)
    }
}
