//
//  FetchPlaylistEvent.swift
//  Playlist
//
//  Analytics event for tracking playlist fetch timing.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation

@AnalyticsEvent
struct FetchPlaylistEvent {
    let duration: TimeInterval
}
