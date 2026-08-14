//
//  DisplayLinkLifecycleTests.swift
//  DebugPanel
//
//  Tests over the HUD's display-link lifecycle: who attaches a 60fps run-loop
//  source, and — the part that regressed — who takes it back down. The HUD is
//  hidden far more often than it is shown, so an attached link is only correct
//  while `DebugHUDState.isVisible`.
//
//  Assertions are deltas against a baseline rather than absolute counts: the
//  link registry is process-global, and `.serialized` only orders tests within
//  this suite, not against sibling suites in the same target.
//
//  Created by Jake Bromberg on 08/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import QuartzCore
import Testing
@testable import DebugPanel

@Suite("Display-link lifecycle", .serialized)
@MainActor
struct DisplayLinkLifecycleTests {
    /// Polls until the registry drains to `expected`, bounded so a failure
    /// reports a wrong count instead of hanging the suite. Teardown hops back
    /// to the main actor from `onTermination`, so it can't be observed
    /// synchronously.
    private func settle(to expected: Int) async -> Int {
        for _ in 0..<200 {
            if DisplayLinkSource.activeLinkCount == expected { return expected }
            await Task.yield()
        }
        return DisplayLinkSource.activeLinkCount
    }

    @Test("constructing a provider attaches no display link")
    func initIsInert() {
        let baseline = DisplayLinkSource.activeLinkCount
        let provider = DebugMetricsProvider()

        #expect(DisplayLinkSource.activeLinkCount == baseline)
        #expect(provider.isRunning == false)
    }

    /// Attachment is synchronous with `start()`, which is what lets the
    /// "nothing attached" assertions here be plain synchronous reads. Attaching
    /// from inside the consuming `Task` instead would make every such assertion
    /// a race the test wins by default — it would pass with the regression
    /// present, on a fast machine, forever.
    @Test("start attaches one link, stop releases it")
    func startThenStopReleasesTheLink() async {
        let baseline = DisplayLinkSource.activeLinkCount
        let provider = DebugMetricsProvider()

        provider.start()
        #expect(provider.isRunning)
        #expect(DisplayLinkSource.activeLinkCount == baseline + 1)

        provider.stop()
        #expect(provider.isRunning == false)
        #expect(await settle(to: baseline) == baseline)
    }

    @Test("start is idempotent — a second call attaches no second link")
    func startIsIdempotent() async {
        let baseline = DisplayLinkSource.activeLinkCount
        let provider = DebugMetricsProvider()

        provider.start()
        provider.start()
        #expect(DisplayLinkSource.activeLinkCount == baseline + 1)

        provider.stop()
        #expect(await settle(to: baseline) == baseline)
    }

    /// `DebugHUD` holds its provider in `@State`, whose initializer expression
    /// is re-evaluated every time the view struct is created even though
    /// SwiftUI keeps only the first instance. Every discarded provider must
    /// therefore cost nothing — otherwise each re-render of the enclosing
    /// `WindowGroup` body strands another 60fps run-loop source.
    @Test("providers that are constructed and discarded strand nothing")
    func discardedProvidersStrandNothing() {
        let baseline = DisplayLinkSource.activeLinkCount

        for _ in 0..<5 {
            _ = DebugMetricsProvider()
        }

        #expect(DisplayLinkSource.activeLinkCount == baseline)
    }

    /// A stream that's never iterated still has to release its link. `AsyncStream`
    /// terminates on the sequence's own deallocation — not on the continuation's,
    /// which a ``DisplayLinkSource`` proxy holds — so this is the one teardown
    /// path with no consumer to cancel. Pinned because it's a stdlib guarantee
    /// the design leans on, and swapping in any other `AsyncSequence` could
    /// quietly drop it.
    @Test("a stream that is never iterated releases its link")
    func discardedStreamReleasesTheLink() async {
        let baseline = DisplayLinkSource.activeLinkCount

        _ = DisplayLinkSource.timestamps()

        #expect(await settle(to: baseline) == baseline)
    }

    /// The regression that made this suite necessary: `CADisplayLink` retains
    /// its target and the run loop retains the link, so a link whose target is
    /// the consumer keeps the consumer alive — and `deinit`, the only caller of
    /// `invalidate()`, never runs. Ending the consuming task must be enough.
    @Test("ending the consuming task tears the link down")
    func cancellingTheConsumerReleasesTheLink() async {
        let baseline = DisplayLinkSource.activeLinkCount

        let task = Task { @MainActor in
            for await _ in DisplayLinkSource.timestamps() {
                // Hold the stream open until cancelled.
            }
        }

        #expect(await settle(to: baseline + 1) == baseline + 1)

        task.cancel()
        _ = await task.value

        #expect(await settle(to: baseline) == baseline)
    }
}
