//
//  LikedSongsEvents.swift
//  Analytics
//
//  Structured analytics for on-device song likes (#492). These events carry
//  no artist or song identity — only lifecycle strings and a coarse store-size
//  bucket — per the privacy invariant (taste data never leaves the device).
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired when a listener likes or unlikes a song. `action` is "like" or
/// "unlike"; `surface` is where the gesture happened ("row", "detail",
/// "liked_tab"); `totalBucket` is the post-toggle store size as a coarse
/// bucket ("0", "1-9", "10-49", "50+") so habit retention is visible without
/// identity. Never carries artist or song data.
@AnalyticsEvent
public struct SongLikeToggled {
    public let action: String
    public let surface: String
    public let totalBucket: String

    public init(action: String, surface: String, totalBucket: String) {
        self.action = action
        self.surface = surface
        self.totalBucket = totalBucket
    }
}
