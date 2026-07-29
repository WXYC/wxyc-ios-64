//
//  PlaybackSourceTests.swift
//  Playback
//
//  Tests for the PlaybackReason -> PlaybackSource attribution mapping (#668).
//
//  Created by Jake Bromberg on 07/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import PlaybackCore

@Suite("PlaybackSource mapping")
struct PlaybackSourceTests {

    @Test("Reasons map to their clean, low-cardinality source", arguments: [
        // Remote command center — collapsed, not guessed (see PlaybackSource.remote).
        (PlaybackReason.remotePlayCommand, PlaybackSource.remote),
        (PlaybackReason.remotePauseCommand, PlaybackSource.remote),
        (PlaybackReason.remoteToggleCommand, PlaybackSource.remote),

        // System-driven auto-resume / auto-pause.
        (PlaybackReason.interruptionBegan, PlaybackSource.auto),
        (PlaybackReason.resumeAfterInterruption, PlaybackSource.auto),
        (PlaybackReason.routeDisconnected, PlaybackSource.auto),
        (PlaybackReason.resumeAfterRouteReconnect, PlaybackSource.auto),
        (PlaybackReason.foregroundNotPlaying, PlaybackSource.auto),
        (PlaybackReason.foregroundToggle, PlaybackSource.auto),
        (PlaybackReason.resumeAfterForeground, PlaybackSource.auto),

        // watchOS / tvOS.
        (PlaybackReason.watchPlayPause, PlaybackSource.watch),
        (PlaybackReason.tvOSCommand, PlaybackSource.app),

        // App entry points.
        (PlaybackReason.carPlay, PlaybackSource.carPlay),
        (PlaybackReason.quickAction, PlaybackSource.app),
        (PlaybackReason.deepLink, PlaybackSource.app),
        (PlaybackReason.handoff, PlaybackSource.app),

        // Siri / Shortcuts / App Intents.
        (PlaybackReason.siriIntent, PlaybackSource.siri),
        (PlaybackReason.playIntent, PlaybackSource.siri),
        (PlaybackReason.pauseIntent, PlaybackSource.siri),
        (PlaybackReason.toggleIntent, PlaybackSource.siri),
        (PlaybackReason.playAudioSchemaIntent, PlaybackSource.siri),

        // The widget's own dedicated reason (#668).
        (PlaybackReason.widgetToggle, PlaybackSource.widget),

        // Test/dev-only reasons never reach production analytics.
        (PlaybackReason.test, PlaybackSource.unknown),
        (PlaybackReason.testToggle, PlaybackSource.unknown),
        (PlaybackReason.userTappedPlay, PlaybackSource.unknown),
        (PlaybackReason.userStartedStream, PlaybackSource.unknown),
        (PlaybackReason.initial, PlaybackSource.unknown),
        (PlaybackReason.errorHandlingTest, PlaybackSource.unknown),
    ])
    func mapsToExpectedSource(reason: PlaybackReason, expected: PlaybackSource) {
        #expect(reason.playbackSource == expected)
    }

    @Test("App-target and PlayerHeaderView reasons (declared outside PlaybackCore) map to .app", arguments: [
        PlaybackReason(rawValue: "header view toggle"),
        PlaybackReason(rawValue: "keyboard shortcut"),
        PlaybackReason(rawValue: "marketing mode"),
    ])
    func crossModuleReasonsMapToApp(reason: PlaybackReason) {
        #expect(reason.playbackSource == .app)
    }

    @Test("An unrecognized reason falls back to .unknown rather than failing to build")
    func unrecognizedReasonFallsBackToUnknown() {
        let reason = PlaybackReason(rawValue: "some reason nobody mapped yet")
        #expect(reason.playbackSource == .unknown)
    }

    @Test(".lockScreen is reserved and currently unreachable from any known reason")
    func lockScreenIsUnreachableToday() {
        let allKnownSources: Set<PlaybackSource> = [
            PlaybackReason.remotePlayCommand, .remotePauseCommand, .remoteToggleCommand,
            .interruptionBegan, .resumeAfterInterruption, .routeDisconnected, .resumeAfterRouteReconnect,
            .foregroundNotPlaying, .foregroundToggle, .resumeAfterForeground,
            .watchPlayPause, .tvOSCommand, .carPlay, .quickAction, .deepLink,
            .siriIntent, .playIntent, .pauseIntent, .toggleIntent, .playAudioSchemaIntent,
            .widgetToggle, .test, .testToggle, .userTappedPlay, .userStartedStream, .initial, .errorHandlingTest,
        ].map(\.playbackSource).reduce(into: Set<PlaybackSource>()) { $0.insert($1) }

        #expect(!allKnownSources.contains(.lockScreen),
               "No reason should map to .lockScreen until a real distinguishing signal exists (see its doc comment)")
    }
}
