//
//  PlayerHeaderViewTests.swift
//  PlayerHeaderView
//
//  Tests for PlayerHeaderView layout and behavior.
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import PlayerHeaderView

@Suite("Playback Controls View Tests")
@MainActor
struct PlaybackControlsViewTests {
    /// The icon must be a function of the same predicate the tap acts on
    /// (`PlaybackController.isPlaybackRequested`). It used to be drawn from
    /// `isPlaying || isLoading` while `toggle(reason:)` branched on `isPlaying`
    /// alone, so during a start that had not yet produced audio the button
    /// promised pause and delivered play — the listener's attempt to cancel a
    /// stuck start silently re-issued it. Sentry IOS-4K/4M/4N.
    @Test("The icon shows pause exactly when a play request is standing")
    func iconTracksTheRequestedPredicate() {
        #expect(
            PlaybackControlsView(isPlaybackRequested: true, onPlayTapped: {}).image
                == Image(systemName: "pause.circle.fill")
        )
        #expect(
            PlaybackControlsView(isPlaybackRequested: false, onPlayTapped: {}).image
                == Image(systemName: "play.circle.fill")
        )
    }
}

@Suite("PlayerHeaderView Tests")
struct PlayerHeaderViewTests {
    @Test("VisualizerConstants has correct default values")
    func visualizerConstantsDefaults() {
        #expect(VisualizerConstants.barAmount == 16)
        #expect(VisualizerConstants.historyLength == 8)
        #expect(VisualizerConstants.magnitudeLimit == 64)
        #expect(VisualizerConstants.updateInterval == 1.0 / 60.0)
    }
    
    @Test("BarData is identifiable and stores correct values")
    func barDataIdentifiable() {
        let barData = BarData(category: "test", value: 10)
        #expect(barData.id == "test")
        #expect(barData.category == "test")
        #expect(barData.value == 10)
    }
    
    @Test("createBarHistory with no values returns zeroed history")
    func createBarHistoryWithNoValues() {
        let history = createBarHistory()
        #expect(history.count == VisualizerConstants.barAmount)
        #expect(history[0].count == VisualizerConstants.historyLength)
        #expect(history[0].allSatisfy { $0 == 0 })
    }
    
    @Test("createBarHistory with preview values returns populated history")
    func createBarHistoryWithPreviewValues() {
        let previewValues: [Float] = [10, 20, 30]
        let history = createBarHistory(previewValues: previewValues)
        #expect(history.count == 3)
        #expect(history[0][0] == 10)
        #expect(history[1][0] == 20)
        #expect(history[2][0] == 30)
    }
}
