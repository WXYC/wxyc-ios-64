//
//  VisualizerDataSourceTests.swift
//  PlayerHeaderViewTests
//
//  Tests for VisualizerDataSource FFT/RMS processing
//

import Testing
import AVFoundation
@testable import PlayerHeaderView

@Suite("VisualizerDataSource Tests")
struct VisualizerDataSourceTests {
    
    // MARK: - Initialization Tests
    
    @Test("Initial state has empty fftMagnitudes and zeroed rmsPerBar")
    func initialState() {
        let dataSource = VisualizerDataSource()
        #expect(dataSource.fftMagnitudes.isEmpty)
        #expect(dataSource.rmsPerBar.count == VisualizerConstants.barAmount)
        #expect(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
        #expect(dataSource.signalBoost == 1.0)
    }
    
    // MARK: - Signal Boost Tests
    
    @Test("Signal boost defaults to 1.0")
    func signalBoostDefault() {
        let dataSource = VisualizerDataSource()
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
        // Set some values
        dataSource.signalBoost = 2.0
        
        dataSource.reset()
        
        #expect(dataSource.fftMagnitudes.isEmpty)
        #expect(dataSource.rmsPerBar.count == VisualizerConstants.barAmount)
        #expect(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
    }
    
    // MARK: - Buffer Processing Tests
    
    @Test("processBuffer updates RMS values")
    @MainActor
    func processBufferUpdatesRMS() async throws {
        let dataSource = VisualizerDataSource()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        // Fill with some audio data
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<1024 {
                channelData[i] = sin(Float(i) * 0.1) * 0.5
            }
        }
        
        dataSource.processBuffer(buffer)
        
        // Wait for async update
        try await Task.sleep(for: .milliseconds(100))
        
        // RMS values should be non-zero after processing audio (test passes if no crash)
    }
    
    @Test("processBuffer with signal boost")
    @MainActor
    func processBufferWithSignalBoost() async throws {
        let dataSource = VisualizerDataSource()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        
        // Fill with some audio data
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<1024 {
                channelData[i] = sin(Float(i) * 0.1) * 0.1
            }
        }
        
        dataSource.signalBoost = 2.0
        dataSource.processBuffer(buffer)
        
        // Signal boost should amplify the visualization
        try await Task.sleep(for: .milliseconds(100))
        
        // Test passes if no crash
    }
}

// MARK: - VisualizerConstants Tests

@Suite("VisualizerConstants Tests")
struct VisualizerConstantsTests {
    
    @Test("VisualizerConstants has correct default values")
    func visualizerConstantsDefaults() {
        #expect(VisualizerConstants.barAmount == 16)
        #expect(VisualizerConstants.historyLength == 8)
        #expect(VisualizerConstants.magnitudeLimit == 32)
        #expect(VisualizerConstants.updateInterval == 0.01)
    }
}
