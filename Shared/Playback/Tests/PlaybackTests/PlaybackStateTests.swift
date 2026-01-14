//
//  PlaybackStateTests.swift
//  Playback
//
//  Tests for PlaybackState enum and its convenience properties.
//
//  Created by Jake Bromberg on 12/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
@testable import PlaybackCore

@Suite("PlaybackState Tests")
struct PlaybackStateTests {

    // MARK: - Convenience Property Tests

    @Test("isPlaying returns true only for playing state")
    func isPlayingProperty() {
        #expect(PlaybackState.playing.isPlaying == true)
        #expect(PlaybackState.idle.isPlaying == false)
        #expect(PlaybackState.loading.isPlaying == false)
        #expect(PlaybackState.stalled.isPlaying == false)
        #expect(PlaybackState.interrupted.isPlaying == false)
        #expect(PlaybackState.error(.unknown("test")).isPlaying == false)
    }

    @Test("isLoading returns true only for loading state")
    func isLoadingProperty() {
        #expect(PlaybackState.loading.isLoading == true)
        #expect(PlaybackState.idle.isLoading == false)
        #expect(PlaybackState.playing.isLoading == false)
        #expect(PlaybackState.stalled.isLoading == false)
        #expect(PlaybackState.interrupted.isLoading == false)
        #expect(PlaybackState.error(.unknown("test")).isLoading == false)
    }

    @Test("isStalled returns true only for stalled state")
    func isStalledProperty() {
        #expect(PlaybackState.stalled.isStalled == true)
        #expect(PlaybackState.idle.isStalled == false)
        #expect(PlaybackState.playing.isStalled == false)
        #expect(PlaybackState.loading.isStalled == false)
        #expect(PlaybackState.interrupted.isStalled == false)
        #expect(PlaybackState.error(.unknown("test")).isStalled == false)
    }

    @Test("isInterrupted returns true only for interrupted state")
    func isInterruptedProperty() {
        #expect(PlaybackState.interrupted.isInterrupted == true)
        #expect(PlaybackState.idle.isInterrupted == false)
        #expect(PlaybackState.playing.isInterrupted == false)
        #expect(PlaybackState.loading.isInterrupted == false)
        #expect(PlaybackState.stalled.isInterrupted == false)
        #expect(PlaybackState.error(.unknown("test")).isInterrupted == false)
    }

    @Test("isError returns true only for error states")
    func isErrorProperty() {
        #expect(PlaybackState.error(.unknown("test")).isError == true)
        #expect(PlaybackState.error(.connectionFailed("network")).isError == true)
        #expect(PlaybackState.error(.decodingFailed("bad data")).isError == true)
        #expect(PlaybackState.error(.audioSessionActivationFailed("session")).isError == true)
        #expect(PlaybackState.error(.maxReconnectAttemptsExceeded).isError == true)
        #expect(PlaybackState.idle.isError == false)
        #expect(PlaybackState.playing.isError == false)
        #expect(PlaybackState.loading.isError == false)
        #expect(PlaybackState.stalled.isError == false)
        #expect(PlaybackState.interrupted.isError == false)
    }

    @Test("isIdle returns true only for idle state")
    func isIdleProperty() {
        #expect(PlaybackState.idle.isIdle == true)
        #expect(PlaybackState.playing.isIdle == false)
        #expect(PlaybackState.loading.isIdle == false)
        #expect(PlaybackState.stalled.isIdle == false)
        #expect(PlaybackState.interrupted.isIdle == false)
        #expect(PlaybackState.error(.unknown("test")).isIdle == false)
    }

    @Test("isActive returns true for playing, loading, or stalled")
    func isActiveProperty() {
        #expect(PlaybackState.playing.isActive == true)
        #expect(PlaybackState.loading.isActive == true)
        #expect(PlaybackState.stalled.isActive == true)
        #expect(PlaybackState.idle.isActive == false)
        #expect(PlaybackState.interrupted.isActive == false)
        #expect(PlaybackState.error(.unknown("test")).isActive == false)
    }

    // MARK: - Equality Tests

    @Test("PlaybackState equality")
    func stateEquality() {
        #expect(PlaybackState.idle == PlaybackState.idle)
        #expect(PlaybackState.playing == PlaybackState.playing)
        #expect(PlaybackState.loading == PlaybackState.loading)
        #expect(PlaybackState.stalled == PlaybackState.stalled)
        #expect(PlaybackState.interrupted == PlaybackState.interrupted)

        #expect(PlaybackState.idle != PlaybackState.playing)
        #expect(PlaybackState.playing != PlaybackState.loading)
    }

    @Test("PlaybackError equality")
    func errorEquality() {
        #expect(PlaybackError.unknown("test") == PlaybackError.unknown("test"))
        #expect(PlaybackError.unknown("a") != PlaybackError.unknown("b"))
        #expect(PlaybackError.connectionFailed("net") == PlaybackError.connectionFailed("net"))
        #expect(PlaybackError.maxReconnectAttemptsExceeded == PlaybackError.maxReconnectAttemptsExceeded)
    }

    @Test("PlaybackState with error equality")
    func errorStateEquality() {
        let error1 = PlaybackState.error(.unknown("test"))
        let error2 = PlaybackState.error(.unknown("test"))
        let error3 = PlaybackState.error(.unknown("different"))

        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    // MARK: - Description Tests

    @Test("PlaybackState description")
    func stateDescription() {
        #expect(PlaybackState.idle.description == "idle")
        #expect(PlaybackState.loading.description == "loading")
        #expect(PlaybackState.playing.description == "playing")
        #expect(PlaybackState.stalled.description == "stalled")
        #expect(PlaybackState.interrupted.description == "interrupted")
        #expect(PlaybackState.error(.unknown("test")).description.contains("error"))
    }

    @Test("PlaybackError description")
    func errorDescription() {
        #expect(PlaybackError.audioSessionActivationFailed("failed").description.contains("audioSessionActivationFailed"))
        #expect(PlaybackError.connectionFailed("net error").description.contains("connectionFailed"))
        #expect(PlaybackError.decodingFailed("bad data").description.contains("decodingFailed"))
        #expect(PlaybackError.maxReconnectAttemptsExceeded.description.contains("maxReconnectAttemptsExceeded"))
        #expect(PlaybackError.unknown("mystery").description.contains("unknown"))
    }
}
