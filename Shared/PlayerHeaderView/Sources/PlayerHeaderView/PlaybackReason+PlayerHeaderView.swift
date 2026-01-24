//
//  PlaybackReason+PlayerHeaderView.swift
//  PlayerHeaderView
//
//  PlayerHeaderView-specific playback reasons for analytics tracking.
//
//  Created by Claude on 01/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import PlaybackCore

extension PlaybackReason {
    /// User tapped play/pause button in header view
    static let headerViewToggle = PlaybackReason(rawValue: "header view toggle")
}
