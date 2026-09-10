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

/// Analytics event capturing the outcome of a single playlist fetch.
///
/// The `@AnalyticsEvent` macro emits each stored property as a snake_case
/// PostHog property, so this fires as `fetch_playlist_event` with
/// `duration`, `api_version`, `result_count`, and `succeeded`. It is emitted on
/// every terminal fetch outcome (non-empty success, empty success, and failure)
/// so per-variant success rate is computable by breaking down on `api_version`
/// and `succeeded` (WXYC/wxyc-ios-64#414, #415).
///
/// `apiVersion` is stored as a `String`. It was an enum's `rawValue` until the
/// v1 path was removed (#262); it is now the constant
/// `PlaylistFetcher.apiVersionTag`, kept on the wire so the `api_version`
/// breakdown still separates this build from the App Store builds through 3.2
/// that report `v1`.
@AnalyticsEvent
struct FetchPlaylistEvent {
    let duration: TimeInterval
    let apiVersion: String
    let resultCount: Int
    let succeeded: Bool
}
