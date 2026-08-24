//
//  PauseWXYCTests.swift
//  WXYCIntents
//
//  Coverage for the Siri pause path. `perform()` itself isn't called here: it
//  captures against `StructuredPostHogAnalytics.shared` and, before this suite
//  existed, stopped the live `AudioPlayerController.shared` singleton directly.
//  The seam is `IntentPlayback.stopAndPublish(reason:context:)` — the whole of
//  what `perform()` now does to playback — and these tests drive that exact
//  call with the exact reason `perform()` passes, the same arrangement
//  `PlayWXYCAudioTests` uses for the start path and for the same reason (see
//  its `MARK: - perform()` note).
//
//  The mirror assertions are the point. A Siri pause arriving while the app is
//  backgrounded used to leave `UserDefaults.wxyc[isPlayingKey]` reading `true`:
//  `WidgetStateService` — the only other writer — is started from the root
//  view's `onAppear`, which an intent-driven launch never reaches. The widget
//  and the Control Center toggle both kept offering "Pause" for audio that had
//  already stopped.
//
//  Created by Jake Bromberg on 08/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation
import PlaybackCore
import Testing
@testable import WXYCIntents

@Suite("PauseWXYC")
struct PauseWXYCTests {
    @Test("Is not discoverable to Siri/Shortcuts as a standalone action")
    func isNotDiscoverable() {
        #expect(PauseWXYC.isDiscoverable == false)
    }

    @Test("Pauses in the background without opening the app")
    func runsInBackgroundWithoutOpeningApp() {
        #expect(PauseWXYC.openAppWhenRun == false)
    }

    /// A throwaway suite per test — the real key lives in the shared app group.
    @MainActor
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PauseWXYCTests-\(UUID().uuidString)")!
    }

    @MainActor
    @Test("perform()'s playback call stops with reason .pauseIntent")
    func performsStopCallUsesPauseIntentReason() {
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true
        controller.isPlaying = true

        IntentPlayback.stopAndPublish(
            reason: .pauseIntent,
            context: "test",
            controller: controller,
            widgetState: isolatedDefaults()
        )

        #expect(controller.stoppedReasons == [.pauseIntent])
    }

    /// Routes the stop through `stopWithAnalytics(reason:)`, not the bare
    /// `stop(reason:)` underneath it. #939: a Siri pause that skips the
    /// analytics wrapper closes the listen without any duration reaching the
    /// #663 series, and `stopWithAnalytics` is where the one-event-per-listen
    /// predicate (#933) lives.
    @MainActor
    @Test("perform()'s playback call goes through the analytics-capturing stop")
    func performsStopCallGoesThroughStopWithAnalytics() {
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true

        IntentPlayback.stopAndPublish(
            reason: .pauseIntent,
            context: "test",
            controller: controller,
            widgetState: isolatedDefaults()
        )

        #expect(controller.events == ["stopWithAnalytics"])
    }

    @MainActor
    @Test("Clears the widget mirror so the control stops offering a pause")
    func clearsWidgetMirror() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: UserDefaults.isPlayingKey)
        let controller = FakeIntentPlaybackController()
        controller.isPlaybackRequested = true
        controller.isPlaying = true

        IntentPlayback.stopAndPublish(
            reason: .pauseIntent,
            context: "test",
            controller: controller,
            widgetState: defaults
        )

        #expect(defaults.bool(forKey: UserDefaults.isPlayingKey) == false)
    }
}
