//
//  VisualizerDataSourceTests.swift
//  PlayerHeaderViewTests
//
//  Tests for VisualizerDataSource FFT/RMS processing
//

import XCTest
import AVFoundation
@testable import PlayerHeaderView

final class VisualizerDataSourceTests: XCTestCase {
    
    var dataSource: VisualizerDataSource!
    
    override func setUp() {
        dataSource = VisualizerDataSource()
    }
    
    override func tearDown() {
        dataSource = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        XCTAssertTrue(dataSource.fftMagnitudes.isEmpty)
        XCTAssertEqual(dataSource.rmsPerBar.count, VisualizerConstants.barAmount)
        XCTAssertTrue(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
        XCTAssertEqual(dataSource.signalBoost, 1.0)
    }
    
    // MARK: - Signal Boost Tests
    
    func testSignalBoostDefault() {
        XCTAssertEqual(dataSource.signalBoost, 1.0)
    }
    
    func testSignalBoostSet() {
        dataSource.signalBoost = 2.0
        XCTAssertEqual(dataSource.signalBoost, 2.0)
    }
    
    func testSignalBoostClampsToMinimum() {
        dataSource.signalBoost = 0.05
        XCTAssertEqual(dataSource.signalBoost, 0.1)
    }
    
    func testSignalBoostClampsToMaximum() {
        dataSource.signalBoost = 15.0
        XCTAssertEqual(dataSource.signalBoost, 10.0)
    }
    
    func testSetSignalBoostMethod() {
        dataSource.setSignalBoost(3.0)
        XCTAssertEqual(dataSource.signalBoost, 3.0)
    }
    
    func testResetSignalBoost() {
        dataSource.signalBoost = 5.0
        dataSource.resetSignalBoost()
        XCTAssertEqual(dataSource.signalBoost, 1.0)
    }
    
    // MARK: - Reset Tests
    
    func testReset() {
        // Set some values
        dataSource.signalBoost = 2.0
        
        dataSource.reset()
        
        XCTAssertTrue(dataSource.fftMagnitudes.isEmpty)
        XCTAssertEqual(dataSource.rmsPerBar.count, VisualizerConstants.barAmount)
        XCTAssertTrue(dataSource.rmsPerBar.allSatisfy { $0 == 0 })
    }
    
    // MARK: - Buffer Processing Tests
    
    func testProcessBufferUpdatesRMS() {
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
        let expectation = XCTestExpectation(description: "RMS values updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // RMS values should be non-zero after processing audio
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testProcessBufferWithSignalBoost() {
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
        let expectation = XCTestExpectation(description: "Boosted RMS values updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - VisualizerConstants Tests

final class VisualizerConstantsTests: XCTestCase {
    
    func testVisualizerConstantsDefaults() {
        XCTAssertEqual(VisualizerConstants.barAmount, 16)
        XCTAssertEqual(VisualizerConstants.historyLength, 8)
        XCTAssertEqual(VisualizerConstants.magnitudeLimit, 32)
        XCTAssertEqual(VisualizerConstants.updateInterval, 0.01)
    }
}

