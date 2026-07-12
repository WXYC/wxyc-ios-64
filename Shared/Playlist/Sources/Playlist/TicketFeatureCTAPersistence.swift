//
//  TicketFeatureCTAPersistence.swift
//  Playlist
//
//  Show/retire state for the Box Office ticket discovery CTA — the "NEW"-stamped
//  card that teaches the ticket feature under the player. It teaches the feature
//  once and then gets out of the way: the moment the user opens a *real* ticket,
//  the lesson has landed and the card retires for good, even if it was never
//  dismissed (the theme-tip `hasEverUsedPicker` pattern, not the Siri one).
//
//  This is the Playlist package's first persistence type; it lives here rather
//  than in the app target so the gating rules are unit-testable in isolation,
//  the way `ThemePickerPersistence` is in the Wallpaper package.
//
//  Created by Jake Bromberg on 07/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation

/// Persistence for the Box Office ticket discovery CTA.
///
/// The card shows on every eligible launch until it retires. It retires when
/// either the user dismisses it (the X) or opens a real Box Office ticket —
/// whichever comes first. Inject a `DefaultsStorage` for testability.
@MainActor
public final class TicketFeatureCTAPersistence: Sendable {

    private enum Keys {
        static let hasSeenRealTicket = "ticketCTA.hasSeenRealTicket"
        static let wasDismissed = "ticketCTA.wasDismissed"
    }

    private let defaults: DefaultsStorage

    /// Creates a persistence instance backed by the given storage.
    ///
    /// - Parameter defaults: The storage to read and write. Defaults to
    ///   `UserDefaults.standard`.
    public init(defaults: DefaultsStorage = UserDefaults.standard) {
        self.defaults = defaults
    }

    // MARK: - State

    /// Whether the user has ever opened a real Box Office ticket. Once true, the
    /// CTA has taught its lesson and never shows again.
    public var hasSeenRealTicket: Bool {
        defaults.bool(forKey: Keys.hasSeenRealTicket)
    }

    /// Whether the user has dismissed the CTA with the X.
    public var wasDismissed: Bool {
        defaults.bool(forKey: Keys.wasDismissed)
    }

    /// Whether the CTA should be shown. True until it retires — i.e. until the
    /// user has either opened a real ticket or dismissed the card.
    public var shouldShow: Bool {
        !hasSeenRealTicket && !wasDismissed
    }

    // MARK: - Recording

    /// Records that the user opened a real Box Office ticket. Idempotent — the
    /// lesson only needs to land once.
    public func recordRealTicketSeen() {
        guard !hasSeenRealTicket else { return }
        defaults.set(true, forKey: Keys.hasSeenRealTicket)
    }

    /// Records that the user dismissed the CTA with the X.
    public func recordDismissed() {
        defaults.set(true, forKey: Keys.wasDismissed)
    }

    // MARK: - Reset

    /// Clears all state, restoring the fresh-install behavior. For the debug
    /// panel's "reset tips" affordance.
    public func resetState() {
        defaults.removeObject(forKey: Keys.hasSeenRealTicket)
        defaults.removeObject(forKey: Keys.wasDismissed)
    }
}
