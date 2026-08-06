//
//  PollUntil.swift
//  Playback
//
//  The one poll-until-deadline helper shared by every Playback test surface,
//  so timeout mechanics can't drift between copies.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Polls `condition` on the main actor until it holds or `timeout` expires,
/// yielding between checks so pending main-actor work — state-stream
/// observers, queued `Task { @MainActor … }` blocks, detached-task
/// continuations — can drain. Returns silently on timeout: pair it with an
/// `#expect` on the same condition so the failure is visible.
///
/// The deadline uses `ContinuousClock`, not `Date`: the wall clock can step
/// (NTP, DST, a manual change) mid-test, and this helper is load-bearing for
/// every deferred-handback assertion in the package.
@MainActor
public func pollUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(5)) async {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        await Task.yield()
    }
}
