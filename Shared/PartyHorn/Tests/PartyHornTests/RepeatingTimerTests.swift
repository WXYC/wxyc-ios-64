//
//  RepeatingTimerTests.swift
//  PartyHorn
//
//  Tests the repeating timer's schedule and its stop/cancellation behavior,
//  driven through an injected sleep so the assertions are deterministic.
//
//  Created by Jake Bromberg on 08/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PartyHorn

@MainActor
@Suite("RepeatingTimer")
struct RepeatingTimerTests {

    @Test("Waits the initial delay, then ticks once per interval")
    func ticksOnSchedule() async {
        let recorder = TimerRecorder()
        let timer = RepeatingTimer(
            initialDelay: .seconds(2),
            interval: .milliseconds(500),
            sleep: { await recorder.recordSleep($0) }
        ) {
            recorder.recordTick()
        }

        timer.start()
        await recorder.waitForTicks(3)
        timer.stop()

        #expect(recorder.sleeps.first == .seconds(2))
        #expect(recorder.sleeps.dropFirst().prefix(2).allSatisfy { $0 == .milliseconds(500) })
    }

    @Test("stop() halts ticking")
    func stopHaltsTicking() async {
        let recorder = TimerRecorder()
        let timer = RepeatingTimer(
            initialDelay: .zero,
            interval: .milliseconds(1),
            sleep: { await recorder.recordSleep($0) }
        ) {
            recorder.recordTick()
        }

        timer.start()
        await recorder.waitForTicks(2)
        timer.stop()

        let settled = recorder.tickCount
        for _ in 0..<50 { await Task.yield() }

        #expect(recorder.tickCount == settled)
    }

    @Test("start() while already running does not start a second loop")
    func startIsIdempotent() async {
        let recorder = TimerRecorder()
        let timer = RepeatingTimer(
            initialDelay: .zero,
            interval: .milliseconds(1),
            sleep: { await recorder.recordSleep($0) }
        ) {
            recorder.recordTick()
        }

        timer.start()
        timer.start()
        await recorder.waitForTicks(1)
        timer.stop()

        // A second loop would keep ticking after the first is cancelled.
        let settled = recorder.tickCount
        for _ in 0..<50 { await Task.yield() }

        #expect(recorder.tickCount == settled)
    }

    @Test("The tick block does not keep its captured object alive")
    func tickBlockDoesNotRetainCaptures() async {
        let recorder = TimerRecorder()
        weak var weakCaptured: Captured?

        do {
            let captured = Captured()
            weakCaptured = captured
            let timer = RepeatingTimer(
                initialDelay: .zero,
                interval: .milliseconds(1),
                sleep: { await recorder.recordSleep($0) }
            ) { [weak captured] in
                captured?.touch()
                recorder.recordTick()
            }
            timer.start()
            await recorder.waitForTicks(1)
            timer.stop()
        }

        await Task.yield()
        #expect(weakCaptured == nil)
    }
}

// MARK: - Helpers

@MainActor
final class TimerRecorder {
    private(set) var sleeps: [Duration] = []
    private(set) var tickCount = 0

    func recordSleep(_ duration: Duration) async {
        sleeps.append(duration)
        await Task.yield()
    }

    func recordTick() {
        tickCount += 1
    }

    func waitForTicks(_ count: Int) async {
        while tickCount < count {
            await Task.yield()
        }
    }
}

@MainActor
final class Captured {
    private(set) var touches = 0
    func touch() { touches += 1 }
}
