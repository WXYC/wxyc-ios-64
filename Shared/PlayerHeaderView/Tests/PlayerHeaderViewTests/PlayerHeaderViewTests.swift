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
            PlaybackControlsView(isPlaybackRequested: true, isPlaying: false, onPlayTapped: {}).image
                == Image(systemName: "pause.circle.fill")
        )
        #expect(
            PlaybackControlsView(isPlaybackRequested: false, isPlaying: false, onPlayTapped: {}).image
                == Image(systemName: "play.circle.fill")
        )
    }

    /// Label and value answer different questions on purpose. The label names
    /// what the tap will do, so it must track the same predicate as the icon —
    /// a VoiceOver user has to be told "Pause" while a start is in flight, or
    /// they get the exact bug this control was fixed for. The value reports
    /// whether audio is actually coming out, which is the only signal either a
    /// listener or a UI test has that a start *succeeded*; driving it from
    /// intent turns `waitUntilValue(playButton, equals: "playing")` in
    /// `PlayWXYCIntentUITests` into an assertion that a tap was recorded.
    @Test(
        "The label tracks the tap's effect; the value tracks actual audio",
        arguments: [
            (requested: true, playing: true, label: "Pause", value: "playing"),
            (requested: true, playing: false, label: "Pause", value: "paused"),
            (requested: false, playing: false, label: "Play", value: "paused")
        ]
    )
    func labelTracksIntentAndValueTracksAudio(
        testCase: (requested: Bool, playing: Bool, label: String, value: String)
    ) {
        let view = PlaybackControlsView(
            isPlaybackRequested: testCase.requested,
            isPlaying: testCase.playing,
            onPlayTapped: {}
        )

        #expect(view.accessibilityLabelText == testCase.label)
        #expect(view.accessibilityValueText == testCase.value)
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

/// The bar count is an init-time parameter of the visualizer pipeline. N = 16
/// is what production constructs and the regression baseline; 18 and 20 prove
/// the pipeline re-buckets for any N rather than carrying 16 around.
@Suite("Visualizer bar count")
struct VisualizerBarCountTests {
    private static let barCounts = [16, 18, 20]
    private static let frameLength = 4_096

    /// Band boundaries the FFT processor computed for N = 16 before the count
    /// became a parameter. Pinning them keeps production output byte-identical.
    private static let baselineBoundaries16 = [
        2, 2, 4, 6, 9, 14, 20, 30, 45, 66, 98, 145, 215, 317, 469, 692, 1023
    ]

    private static func makeSignal(_ sample: (Int) -> Float) -> [Float] {
        (0..<frameLength).map(sample)
    }

    @Test("FFT band boundaries for N = 16 match the pre-parameterization baseline")
    func fftBoundariesBaseline() {
        let processor = FFTProcessor(barCount: 16, normalizationMode: .none, frequencyWeightingExponent: 0)
        #expect(processor.bandBoundaries == Self.baselineBoundaries16)
    }

    @Test("FFT band boundaries partition the usable bins into N ordered bands", arguments: barCounts)
    func fftBoundariesPartitionBins(barCount: Int) {
        let processor = FFTProcessor(barCount: barCount, normalizationMode: .none, frequencyWeightingExponent: 0)
        let boundaries = processor.bandBoundaries

        #expect(boundaries.count == barCount + 1)
        #expect(boundaries.first == 2)
        #expect(boundaries.last == 1023)
        #expect(zip(boundaries, boundaries.dropFirst()).allSatisfy { $0 <= $1 })

        // Adjacent bands share an edge, so band widths sum to the whole span:
        // no bin is dropped or counted twice.
        let widths = zip(boundaries, boundaries.dropFirst()).map { $1 - $0 }
        #expect(widths.reduce(0, +) == 1023 - 2)
    }

    @Test("FFT output has one value per bar", arguments: barCounts)
    func fftOutputCount(barCount: Int) throws {
        let processor = FFTProcessor(barCount: barCount, normalizationMode: .perBandEMA, frequencyWeightingExponent: 1)
        var signal = Self.makeSignal { sin(2 * .pi * 1_000 / 44_100 * Float($0)) }
        let output = try signal.withUnsafeMutableBufferPointer { pointer in
            processor.process(data: try #require(pointer.baseAddress), frameLength: Self.frameLength)
        }
        #expect(output.count == barCount)
    }

    @Test("RMS output has one value per bar and conserves energy", arguments: barCounts)
    func rmsConservesEnergy(barCount: Int) throws {
        let processor = RMSProcessor(barCount: barCount, normalizationMode: .none)
        var signal = Self.makeSignal { 0.5 * sin(2 * .pi * 440 / 44_100 * Float($0)) }
        let samplesPerBar = Self.frameLength / barCount
        let covered = samplesPerBar * barCount
        let inputEnergy = signal.prefix(covered).reduce(Float(0)) { $0 + $1 * $1 }

        let output = try signal.withUnsafeMutableBufferPointer { pointer in
            processor.process(data: try #require(pointer.baseAddress), frameLength: Self.frameLength)
        }

        #expect(output.count == barCount)
        // Undo the processor's display scaling (magnitudeLimit * 2) to recover each bar's RMS.
        let outputEnergy = output.reduce(Float(0)) {
            let rms = $1 / (VisualizerConstants.magnitudeLimit * 2)
            return $0 + rms * rms * Float(samplesPerBar)
        }
        #expect(abs(outputEnergy - inputEnergy) <= inputEnergy * 1e-4)
    }

    @Test("Per-band normalizer sizes itself to the band count", arguments: barCounts)
    func perBandNormalizerCoversEveryBand(barCount: Int) {
        let normalizer = NormalizationMode.perBandEMA.createNormalizer(bandCount: barCount)
        var values = [Float](repeating: 3, count: barCount)
        normalizer.normalize(&values, outputScale: 10)
        #expect(values.allSatisfy { $0 == 10 })
    }

    @Test("VisualizerDataSource sizes its output from the constructed count", arguments: barCounts)
    func dataSourceCount(barCount: Int) {
        let dataSource = VisualizerDataSource(barCount: barCount)
        #expect(dataSource.barCount == barCount)
        #expect(dataSource.rmsPerBar.count == barCount)
    }

    @Test("VisualizerDataSource defaults to the production bar count")
    func dataSourceDefaultCount() {
        #expect(VisualizerDataSource().barCount == VisualizerConstants.barAmount)
    }

    @Test("createBarHistory sizes one row per bar", arguments: barCounts)
    func barHistoryCount(barCount: Int) {
        let history = createBarHistory(barCount: barCount)
        #expect(history.count == barCount)
        #expect(history.allSatisfy { $0.count == VisualizerConstants.historyLength })
    }
}
