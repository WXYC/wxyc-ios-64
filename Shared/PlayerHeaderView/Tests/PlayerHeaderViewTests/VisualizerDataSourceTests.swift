//
//  VisualizerDataSourceTests.swift
//  PlayerHeaderView
//
//  Tests for VisualizerDataSource FFT/RMS processing, delay buffer integration,
//  and stream consumption lifecycle.
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import AVFoundation
import os
@testable import PlayerHeaderView

@Suite("VisualizerDataSource Tests")
struct VisualizerDataSourceTests {
    
    // MARK: - Initialization Tests

    @Test("Initial state has empty fftMagnitudes and zeroed rmsPerBar")
    func initialState() {
        // Clear UserDefaults to ensure clean state
        UserDefaults.standard.removeObject(forKey: "visualizer.signalBoost")
        let dataSource = VisualizerDataSource()
        #expect(dataSource.fftMagnitudes.isEmpty)
        #expect(dataSource.rmsPerBar.count == VisualizerConstants.barAmount)
        #expect(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
    }

    // MARK: - Signal Boost Tests

    @Test("Signal boost defaults to 1.0 after reset")
    func signalBoostDefault() {
        let dataSource = VisualizerDataSource()
        dataSource.reset()  // Reset to ensure default value
        #expect(dataSource.signalBoost == 1.0)
    }

    @Test("Signal boost can be set")
    func signalBoostSet() {
        let dataSource = VisualizerDataSource()
        dataSource.signalBoost = 2.0
        #expect(dataSource.signalBoost == 2.0)
    }

    @Test("Signal boost clamps to minimum of 0.1")
    func signalBoostClampsToMinimum() {
        let dataSource = VisualizerDataSource()
        dataSource.signalBoost = 0.05
        #expect(dataSource.signalBoost == 0.1)
    }

    @Test("Signal boost clamps to maximum of 10.0")
    func signalBoostClampsToMaximum() {
        let dataSource = VisualizerDataSource()
        dataSource.signalBoost = 15.0
        #expect(dataSource.signalBoost == 10.0)
    }

    @Test("setSignalBoost method works")
    func setSignalBoostMethod() {
        let dataSource = VisualizerDataSource()
        dataSource.setSignalBoost(3.0)
        #expect(dataSource.signalBoost == 3.0)
    }

    @Test("resetSignalBoost resets to 1.0")
    func resetSignalBoost() {
        let dataSource = VisualizerDataSource()
        dataSource.signalBoost = 5.0
        dataSource.resetSignalBoost()
        #expect(dataSource.signalBoost == 1.0)
    }

    // MARK: - Reset Tests

    @Test("reset clears fftMagnitudes and zeroes rmsPerBar")
    func reset() {
        let dataSource = VisualizerDataSource()
        dataSource.signalBoost = 2.0
        
        dataSource.reset()
        
        #expect(dataSource.fftMagnitudes.isEmpty)
        #expect(dataSource.rmsPerBar.count == VisualizerConstants.barAmount)
        #expect(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
    }
    
    // MARK: - Output Latency
    
    @Test("outputLatency defaults to 0")
    func outputLatencyDefault() {
        let dataSource = VisualizerDataSource()
        #expect(dataSource.outputLatency == 0)
    }

    // MARK: - isActive
        
    @Test("isActive is false initially")
    func isActiveInitial() {
        let dataSource = VisualizerDataSource()
        #expect(dataSource.isActive == false)
    }

    // MARK: - Delay Buffer Integration

    @Test("processBuffer + dequeueNextFrame with zero latency updates fftMagnitudes and rmsPerBar")
    @MainActor
    func processBufferThenDequeue() {
        let dataSource = VisualizerDataSource()
        dataSource.outputLatency = 0
        let buffer = makeAudioBuffer()
    
        dataSource.processBuffer(buffer)
        dataSource.dequeueNextFrame()

        // After processing a non-silent buffer with zero latency, at least one processor
        // should produce non-trivial output
        let hasOutput = !dataSource.fftMagnitudes.isEmpty ||
            dataSource.rmsPerBar.contains(where: { $0 > 0 })
        #expect(hasOutput, "Expected non-trivial output after processBuffer + dequeueNextFrame")
    }

    @Test("processBuffer + dequeueNextFrame with 2s latency does NOT update values immediately")
    @MainActor
    func processBufferWithLatencyDoesNotUpdateImmediately() {
        let dataSource = VisualizerDataSource()
        dataSource.outputLatency = 2.0
        let buffer = makeAudioBuffer()

        dataSource.processBuffer(buffer)
        dataSource.dequeueNextFrame()

        // With 2s latency the frame is not yet eligible, so output stays at initial state
        #expect(dataSource.fftMagnitudes.isEmpty)
        #expect(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
    }

    // MARK: - Stream Consumption Lifecycle

    @Test("startConsuming sets isActive to true")
    @MainActor
    func startConsumingSetsIsActive() {
        let dataSource = VisualizerDataSource()
        let stream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }

        dataSource.startConsuming(stream: stream)

        #expect(dataSource.isActive == true)
        dataSource.stopConsuming()
    }

    @Test("stopConsuming cancels task")
    @MainActor
    func stopConsumingCancelsTask() async throws {
        let dataSource = VisualizerDataSource()
        let flag = CancellationFlag()

        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.onTermination = { @Sendable _ in
                flag.set()
            }
        }

        dataSource.startConsuming(stream: stream)
        dataSource.stopConsuming()

        // Give a moment for task cancellation to propagate
        try await Task.sleep(for: .milliseconds(50))

        #expect(flag.value)
    }

    @Test("isActive stays true after stopConsuming when buffer has frames, becomes false after draining")
    @MainActor
    func isActiveDrainsBuffer() {
        let dataSource = VisualizerDataSource()
        dataSource.outputLatency = 0
        let buffer = makeAudioBuffer()

        // Simulate: consuming was active and frames were enqueued
        let stream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        dataSource.startConsuming(stream: stream)
        dataSource.processBuffer(buffer)

        // Stop consuming - buffer still has a frame
        dataSource.stopConsuming()
        #expect(dataSource.isActive == true, "isActive should be true while buffer has frames")

        // Drain the buffer
        dataSource.dequeueNextFrame()
        #expect(dataSource.isActive == false, "isActive should be false after buffer is drained")
    }

    @Test("Calling startConsuming while already consuming cancels previous task")
    @MainActor
    func startConsumingCancelsPrevious() async throws {
        let dataSource = VisualizerDataSource()
        let flag = CancellationFlag()

        let firstStream = AsyncStream<AVAudioPCMBuffer> { continuation in
            continuation.onTermination = { @Sendable _ in
                flag.set()
            }
        }
        let secondStream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }

        dataSource.startConsuming(stream: firstStream)
        dataSource.startConsuming(stream: secondStream)

        try await Task.sleep(for: .milliseconds(50))

        #expect(flag.value, "First stream should be terminated when startConsuming is called again")
        dataSource.stopConsuming()
    }

    // MARK: - Buffer Processing (existing tests, updated for delay buffer)

    @Test("processBuffer does not crash with signal boost")
    func processBufferWithSignalBoost() {
        let dataSource = VisualizerDataSource()
        dataSource.signalBoost = 2.0
        let buffer = makeAudioBuffer(amplitude: 0.1)

        dataSource.processBuffer(buffer)
        // Test passes if no crash
    }

    @Test("reset clears delay buffer and resets isActive")
    @MainActor
    func resetClearsDelayBuffer() {
        let dataSource = VisualizerDataSource()
        dataSource.outputLatency = 0
        let buffer = makeAudioBuffer()

        let stream = AsyncStream<AVAudioPCMBuffer> { $0.finish() }
        dataSource.startConsuming(stream: stream)
        dataSource.processBuffer(buffer)
        #expect(dataSource.isActive == true)

        dataSource.reset()

        #expect(dataSource.isActive == false)
        dataSource.dequeueNextFrame()
        #expect(dataSource.fftMagnitudes.isEmpty)
    }
}

// MARK: - VisualizerConstants Tests

@Suite("VisualizerConstants Tests")
struct VisualizerConstantsTests {

    @Test("VisualizerConstants has correct default values")
    func visualizerConstantsDefaults() {
        #expect(VisualizerConstants.barAmount == 16)
        #expect(VisualizerConstants.historyLength == 8)
        #expect(VisualizerConstants.magnitudeLimit == 64)
        #expect(VisualizerConstants.updateInterval == 1.0 / 60.0)
    }
}

// MARK: - Test Helpers

/// Thread-safe boolean flag for tracking stream termination in tests.
private final class CancellationFlag: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: false)

    var value: Bool { storage.withLock { $0 } }

    func set() { storage.withLock { $0 = true } }
}

private func makeAudioBuffer(amplitude: Float = 0.5) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
    buffer.frameLength = 1024

    if let channelData = buffer.floatChannelData?[0] {
        for i in 0..<1024 {
            channelData[i] = sin(Float(i) * 0.1) * amplitude
        }
    }

    return buffer
}
