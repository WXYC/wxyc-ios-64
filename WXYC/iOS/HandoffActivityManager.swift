//
//  HandoffActivityManager.swift
//  WXYC
//
//  Owns the Handoff NSUserActivity and ties its current-ness to playback:
//  the live stream has no position to serialize, so "handing off" reduces
//  to "start playing the live stream on the receiving device," advertised
//  only while this device is actually playing.
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation

/// Protocol abstracting the pair of `NSUserActivity` methods this manager
/// needs, for testability.
@MainActor
protocol CurrentActivityControlling: AnyObject {
    func becomeCurrent()
    func resignCurrent()
}

extension NSUserActivity: CurrentActivityControlling {}

/// Owns a playback-gated Handoff `NSUserActivity`. This class is a simple
/// processor — callers are responsible for observing playback state and
/// calling ``setPlaybackState(isPlaying:)``.
@MainActor
final class HandoffActivityManager {
    private let makeActivity: () -> CurrentActivityControlling
    private var currentActivity: CurrentActivityControlling?

    init(makeActivity: @escaping () -> CurrentActivityControlling = { HandoffActivityManager.makeDefaultActivity() }) {
        self.makeActivity = makeActivity
    }

    static func makeDefaultActivity() -> NSUserActivity {
        let activity = NSUserActivity(activityType: WXYCUserActivity.play)
        activity.title = "Play \(RadioStation.WXYC.name)"
        activity.isEligibleForHandoff = true
        activity.userInfo = ["origin": "handoff"]
        return activity
    }

    /// Advertise a Handoff activity only while the stream is actually playing.
    func setPlaybackState(isPlaying: Bool) {
        // `currentActivity != nil` is the single source of truth for "currently
        // advertising a Handoff activity", so the transition guard reads it
        // directly rather than mirroring it into a second stored flag.
        guard isPlaying != (currentActivity != nil) else { return }
        if isPlaying {
            let activity = makeActivity()
            activity.becomeCurrent()
            currentActivity = activity
        } else {
            currentActivity?.resignCurrent()
            currentActivity = nil
        }
    }
}
