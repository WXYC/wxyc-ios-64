//
//  PrematureAccessCounter.swift
//  MusicShareKit
//
//  Counts things that happen before there is anywhere to report them (#998).
//  Used by MusicShareKit.deviceFingerprint's pre-configure(_:) read path, which
//  cannot capture analytics at the moment it runs because the configuration —
//  where the analytics service lives — does not exist yet.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Synchronization

/// A thread-safe, monotonic count of events that occur before an analytics
/// service exists to receive them.
///
/// Deliberately has no drain or reset. In production the count is read exactly
/// once, by the first `MusicShareKit.reconfigure(_:)` of the process — which
/// `configure(_:)`'s once-per-process gate guarantees is also the last — so
/// draining would buy nothing there while making the value depend on which
/// suite in a parallel test run happened to read it first.
///
/// State lives in a `Mutex` rather than an `NSLock`, per `docs/swift-style.md`,
/// and rather than an `Atomic` because `count` and `record()` must agree on a
/// single value even though nothing here is `await`-ed.
final class PrematureAccessCounter: Sendable {
    private let value = Mutex(0)

    /// How many accesses have been recorded. Reading does not reset.
    var count: Int {
        value.withLock { $0 }
    }

    /// Records one access.
    func record() {
        value.withLock { $0 += 1 }
    }
}
