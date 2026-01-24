//
//  PlaybackReason+App.swift
//  WXYC
//
//  App-specific playback reasons for analytics tracking.
//
//  Created by Claude on 01/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import PlaybackCore

extension PlaybackReason {
    /// User tapped keyboard shortcut (spacebar)
    static let keyboardShortcut = PlaybackReason(rawValue: "keyboard shortcut")

    /// User tapped play button in header view
    static let headerViewToggle = PlaybackReason(rawValue: "header view toggle")

    /// Marketing mode initiated playback
    static let marketingMode = PlaybackReason(rawValue: "marketing mode")
}
