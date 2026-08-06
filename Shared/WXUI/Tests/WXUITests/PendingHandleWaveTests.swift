//
//  PendingHandleWaveTests.swift
//  WXUI
//
//  Verifies the pure gate that holds a one-shot handle wave until it can actually
//  be seen — the app foregrounded and the handle on-screen. A sign-on that lands
//  while the app is backgrounded (or scrolled off) must not fire unseen; it waits
//  for the next visible moment, and the most recent request wins.
//
//  Created by Jake Bromberg on 08/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import WXUI

@Suite("Pending handle wave")
struct PendingHandleWaveTests {

    @Test("Plays immediately when the handle is already visible")
    func playsWhenVisible() {
        var gate = PendingHandleWave()
        #expect(gate.request(delay: 0, canPlayNow: true) == 0)
        #expect(gate.deferredDelay == nil)
    }

    @Test("Defers when the handle can't be seen yet")
    func defersWhenHidden() {
        var gate = PendingHandleWave()
        #expect(gate.request(delay: 0.5, canPlayNow: false) == nil)
        #expect(gate.deferredDelay == 0.5)
    }

    @Test("Stays deferred while the gate is still closed")
    func staysDeferredUntilVisible() {
        var gate = PendingHandleWave()
        _ = gate.request(delay: 0, canPlayNow: false)
        #expect(gate.resume(canPlayNow: false) == nil)
        #expect(gate.deferredDelay == 0)
    }

    @Test("Replays the deferred wave once the gate opens, then holds nothing")
    func replaysOnceWhenGateOpens() {
        var gate = PendingHandleWave()
        _ = gate.request(delay: 0.5, canPlayNow: false)
        #expect(gate.resume(canPlayNow: true) == 0.5)
        #expect(gate.deferredDelay == nil)
        // A second gate-open must not replay an already-flushed wave.
        #expect(gate.resume(canPlayNow: true) == nil)
    }

    @Test("Resuming with nothing pending is a no-op")
    func resumeWithoutPendingIsNoOp() {
        var gate = PendingHandleWave()
        #expect(gate.resume(canPlayNow: true) == nil)
        #expect(gate.deferredDelay == nil)
    }

    @Test("The most recent request supersedes an older deferred one")
    func latestDeferredRequestWins() {
        var gate = PendingHandleWave()
        _ = gate.request(delay: 0.5, canPlayNow: false)   // launch wave, deferred
        _ = gate.request(delay: 0, canPlayNow: false)     // DJ change while still hidden
        #expect(gate.deferredDelay == 0)
        #expect(gate.resume(canPlayNow: true) == 0)
    }

    @Test("An immediate request clears a wave that was waiting")
    func immediateRequestClearsDeferral() {
        var gate = PendingHandleWave()
        _ = gate.request(delay: 0.5, canPlayNow: false)   // deferred while hidden
        #expect(gate.request(delay: 0, canPlayNow: true) == 0)
        #expect(gate.deferredDelay == nil)
        // Nothing left to replay on the next gate change.
        #expect(gate.resume(canPlayNow: true) == nil)
    }
}
