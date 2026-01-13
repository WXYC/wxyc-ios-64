//
//  ReviewRequestService.swift
//  AppServices
//
//  Service that tracks user engagement actions and triggers review requests.
//  Tracks three qualifying actions: playback started, request sent, song added to library.
//  After any combination of 3 actions, triggers a one-time review request per version.
//

import Caching
import Foundation

/// Service that tracks user engagement actions and triggers review requests.
@MainActor
@Observable
public final class ReviewRequestService {

    // MARK: - Configuration

    private let threshold = 3
    private let minimumVersionForReview: String

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let actionCount = "reviewRequest.actionCount"
        static let lastRequestedVersion = "reviewRequest.lastRequestedVersion"
    }

    // MARK: - State

    /// Observable property that triggers review request in UI.
    /// When this becomes true, the UI should call `requestReview()` and then `didRequestReview()`.
    public private(set) var shouldRequestReview = false

    private let storage: DefaultsStorage

    // MARK: - Initialization

    /// Creates a new ReviewRequestService.
    /// - Parameters:
    ///   - storage: Storage for persisting action counts and version info. Uses app group defaults by default.
    ///   - minimumVersionForReview: The minimum app version that should trigger reviews. Bump this to re-enable reviews.
    public init(
        storage: DefaultsStorage = UserDefaults.wxyc,
        minimumVersionForReview: String
    ) {
        self.storage = storage
        self.minimumVersionForReview = minimumVersionForReview
    }

    // MARK: - Public API

    /// Record that playback was started by the user.
    public func recordPlaybackStarted() {
        recordAction()
    }

    /// Record that a song request was sent to the station.
    public func recordRequestSent() {
        recordAction()
    }

    /// Record that a song was added to the user's library.
    public func recordSongAddedToLibrary() {
        recordAction()
    }

    /// Called by UI after the review request has been shown.
    /// Resets the action count and stores the current version.
    public func didRequestReview() {
        shouldRequestReview = false
        storage.set(0, forKey: Keys.actionCount)
        storage.set(minimumVersionForReview, forKey: Keys.lastRequestedVersion)
    }

    // MARK: - Private

    private func recordAction() {
        let currentCount = storage.integer(forKey: Keys.actionCount)
        let newCount = currentCount + 1
        storage.set(newCount, forKey: Keys.actionCount)

        if newCount >= threshold && shouldTriggerReview() {
            shouldRequestReview = true
        }
    }

    private func shouldTriggerReview() -> Bool {
        guard let lastRequestedVersion = storage.string(forKey: Keys.lastRequestedVersion) else {
            // Never requested before
            return true
        }

        // Compare versions using numeric comparison
        return compareVersions(minimumVersionForReview, isGreaterThan: lastRequestedVersion)
    }

    /// Compares two semantic version strings.
    /// Returns true if version1 is greater than version2.
    private func compareVersions(_ version1: String, isGreaterThan version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Components.count, v2Components.count)

        for i in 0..<maxLength {
            let v1Part = i < v1Components.count ? v1Components[i] : 0
            let v2Part = i < v2Components.count ? v2Components[i] : 0

            if v1Part > v2Part {
                return true
            } else if v1Part < v2Part {
                return false
            }
        }

        return false
    }
}
