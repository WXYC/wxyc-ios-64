//
//  WidgetEngagementStore.swift
//  AppServices
//
//  The app-group channel carrying the signals the widget's timeline provider
//  needs to pick a refresh cadence: when the user last engaged, and whether
//  playback is live.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation

/// Reads the freshness signals shared between the app and the widget
/// extension, and owns the engagement half of them.
///
/// The widget runs in its own process and cannot see the app's memory, so
/// ``WidgetRefreshSchedule``'s inputs have to travel through the
/// `group.wxyc.iphone` app group. This type owns the engagement timestamp
/// outright — ``WidgetStateService`` writes it, the timeline provider reads
/// it. For `isPlaying` it is one reader among several rather than the owner;
/// see ``isPlaying``.
///
/// Cheap to construct, and every property is a **live read** rather than a
/// snapshot — the provider builds a fresh one per timeline request, and two
/// reads in the same request can disagree if the app writes between them.
public struct WidgetEngagementStore: Sendable {

    // MARK: - Keys

    /// When the user last did something that implies they care about the
    /// widget being current.
    private static let lastEngagementKey = "widget.lastEngagement"

    /// Deliberately the same bare `"isPlaying"` key the widget's `PlayButton`
    /// already binds with `@AppStorage` and `PlaybackStateProvider` already
    /// reads — this store joins those readers rather than introducing a
    /// parallel flag that could disagree with the glyph on screen.
    private static let isPlayingKey = "isPlaying"

    // MARK: - Storage

    private let storage: DefaultsStorage

    /// - Parameter storage: Where the signals live. Defaults to the shared app
    ///   group, which is the only store both processes can see; tests pass an
    ///   `InMemoryDefaults` to stay out of the process-global suite.
    public init(storage: DefaultsStorage = UserDefaults.wxyc) {
        self.storage = storage
    }

    // MARK: - Engagement

    /// When the user last engaged, or `nil` if nothing has been recorded.
    ///
    /// Stored as a `Double` of seconds since the Unix epoch rather than an
    /// archived `Date`: it crosses a process boundary and gets read on the
    /// widget's timeline path, where a plain scalar can't fail to decode.
    public var lastEngagement: Date? {
        let seconds = storage.double(forKey: Self.lastEngagementKey)
        // `double(forKey:)` answers 0 for both "absent" and "the epoch". No
        // real engagement is stamped at 1970, so treating them alike is safe
        // and avoids an `object(forKey:)` cast on the read path.
        guard seconds != 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Stamps an engagement.
    ///
    /// Call this when the user does something that says they are paying
    /// attention — foregrounding the app, starting playback, tapping the
    /// widget. It restarts ``WidgetRefreshSchedule``'s decay at the hot tier.
    /// Do *not* call it for things that merely happen near the user, such as a
    /// stream ending or a background fetch completing.
    public func recordEngagement(at date: Date = .now) {
        storage.set(date.timeIntervalSince1970, forKey: Self.lastEngagementKey)
    }

    // MARK: - Playback

    /// Whether playback is currently active.
    ///
    /// Read-only here. ``WidgetStateService`` owns the write, because it is
    /// the only thing observing the playback controller.
    public var isPlaying: Bool {
        storage.bool(forKey: Self.isPlayingKey)
    }
}
