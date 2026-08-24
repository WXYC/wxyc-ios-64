//
//  WidgetToggleWXYCTests.swift
//  WXYCIntents
//
//  Structural coverage for the widget-only toggle intent (#668). `perform()`
//  itself isn't exercised here — like `ToggleWXYC`/`PlayWXYC`/`PauseWXYC`, it
//  drives the live `AudioPlayerController.shared` singleton and isn't
//  DI-seamed for a unit test (see `IntentPlaybackTests` for the one piece of
//  intent logic that is: the shared await-playback-start loop). What matters
//  here is that this intent stays a widget-only implementation detail — never
//  surfaced to Siri/Shortcuts, which would defeat the point of splitting it
//  from `ToggleWXYC` (#668) — and that every widget call site hands the system
//  an instance with `value` actually assigned, which is the one thing no test
//  in the widget target can check (that target has none).
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYCIntents

@Suite("WidgetToggleWXYC")
struct WidgetToggleWXYCTests {
    @Test("Is not discoverable to Siri/Shortcuts — widget-button use only")
    func isNotDiscoverable() {
        #expect(WidgetToggleWXYC.isDiscoverable == false)
    }

    @Test("Runs in the background without opening the app")
    func runsInBackgroundWithoutOpeningApp() {
        #expect(WidgetToggleWXYC.openAppWhenRun == false)
    }

    /// The initializer every widget-style control must use, and the reason it
    /// exists. `SetValueIntent` makes `value` a required, non-defaulted
    /// parameter, and WidgetKit does not fill those in: "unlike app intents you
    /// define for system functionality like Siri, widgets don't resolve
    /// parameters for app intents"
    /// (developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
    /// An unassigned `value` means the system never enters `perform()` at all.
    @Test("Assigns `value` — widget controls have to, because WidgetKit won't resolve it", arguments: [false, true])
    @available(iOS 18.2, macOS 15.2, watchOS 11.2, tvOS 18.2, *)
    func assignsValueForWidgetControls(isPlaying: Bool) {
        let intent = WidgetToggleWXYC(togglingFrom: isPlaying)

        #expect(intent.$value.valueState == .set(!isPlaying))
    }

    /// Non-vacuity guard for the test above: it only means something if an
    /// unassigned `value` is observably different, and this pins the exact
    /// shape that broke the Home Screen button — `WidgetToggleWXYC()` handed
    /// straight to `Button(intent:)`. `valueState` is the only non-trapping
    /// read of the parameter; `intent.value` force-unwraps and would crash the
    /// test runner rather than fail it.
    @Test("The bare initializer leaves `value` unset — the shape no widget call site may use")
    @available(iOS 18.2, macOS 15.2, watchOS 11.2, tvOS 18.2, *)
    func bareInitializerLeavesValueUnset() {
        #expect(WidgetToggleWXYC().$value.valueState == .unset)
    }
}
