//
//  Duration+TimeInterval.swift
//  Core
//
//  Bridges Swift's `Duration` to the `TimeInterval` that Foundation APIs and
//  analytics payloads still speak in.
//
//  Created by Jake Bromberg on 08/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public extension Duration {
    /// The duration in seconds.
    ///
    /// Both halves of `components` are read: the attosecond half carries
    /// everything below a whole second, and a conversion that used only
    /// `components.seconds` would floor a 12.4 s value to 12 — most of the
    /// resolution, for the sub-minute spans this is usually applied to.
    ///
    /// Destructured in one access rather than read twice. `components` is not
    /// `@inlinable` in the shipped stdlib, so its 128-bit division cannot be
    /// inlined or common-subexpressioned away; two reads do that division
    /// twice and discard half of each result. Every `Timer.duration()` call
    /// site routes through here.
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
