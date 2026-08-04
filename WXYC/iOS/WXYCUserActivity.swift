//
//  WXYCUserActivity.swift
//  WXYC
//
//  The shared "play WXYC" NSUserActivity type constant, plus the pure,
//  testable decision that attributes a continued activity of that type to a
//  PlaybackReason (Handoff vs. quick action / Siri prediction / Spotlight).
//
//  Created by Jake Bromberg on 07/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PlaybackCore

enum WXYCUserActivity {
    /// The activity type shared by the home screen quick action, the donated
    /// Siri/Spotlight prediction activity, and the playback-gated Handoff
    /// activity `HandoffActivityManager` owns. All four `"org.wxyc.iphoneapp.play"`
    /// call sites in the app target read this constant instead of repeating
    /// the literal.
    ///
    /// Not `nonisolated`: `WXYCApp.performDonation()` (#740) is the one
    /// caller that runs off the main actor, and it reads this from inside
    /// its own `await MainActor.run { }` hop rather than directly from
    /// non-isolated code, so this stays main-actor isolated like every
    /// other declaration in this module (`SWIFT_DEFAULT_ACTOR_ISOLATION =
    /// MainActor`) without needing an explicit override.
    static let play = "org.wxyc.iphoneapp.play"

    /// The `PlaybackReason` to attribute to a continued `NSUserActivity` of
    /// this type, or `nil` if `activityType` isn't ours.
    ///
    /// `HandoffActivityManager.makeDefaultActivity()` stamps
    /// `userInfo["origin"] == "handoff"` on the activity it hands to
    /// `becomeCurrent()`, so a continuation carrying that marker came from a
    /// real cross-device Handoff. Everything else of this type — the home
    /// screen quick action, and the Siri-prediction/Spotlight activity
    /// `donateSiriIntent()` donates — keeps the existing `.quickAction`
    /// attribution, so nothing already shipping gets mislabeled.
    static func continuationReason(activityType: String, userInfo: [AnyHashable: Any]?) -> PlaybackReason? {
        guard activityType == play else { return nil }
        if (userInfo?["origin"] as? String) == "handoff" {
            return .handoff
        }
        return .quickAction
    }
}
