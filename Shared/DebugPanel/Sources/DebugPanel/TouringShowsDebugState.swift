//
//  TouringShowsDebugState.swift
//  DebugPanel
//
//  Observable singleton for forcing a mock "Box Office" touring-show ticket onto
//  the now-playing (first) playlist item during testing, so the ticket can be
//  exercised in the running app without waiting for a real matching show.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Shared debug state for the touring-shows Box Office ticket.
///
/// Lets you preview the ticket on the first (now-playing) playcut's detail view
/// without a real upcoming show in the data source.
@MainActor
@Observable
public final class TouringShowsDebugState {
    public static let shared = TouringShowsDebugState()

    /// When true, the now-playing (first) playlist item gets a mock upcoming show
    /// so its detail view renders the Box Office ticket.
    public var mockFirstItemEnabled: Bool {
        didSet {
            UserDefaults.standard.set(mockFirstItemEnabled, forKey: Self.storageKey)
        }
    }

    /// Runtime-only (not persisted): the id of the current first/now-playing
    /// playcut. Published by `PlaylistView` on every playlist update so the
    /// provider can scope the mock to exactly that row rather than every playcut.
    public var firstPlaycutID: UInt64?

    private static let storageKey = "TouringShowsDebug.mockFirstItem"

    private init() {
        self.mockFirstItemEnabled = UserDefaults.standard.bool(forKey: Self.storageKey)
    }
}
