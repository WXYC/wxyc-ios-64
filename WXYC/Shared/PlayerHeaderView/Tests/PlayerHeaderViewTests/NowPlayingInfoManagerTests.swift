//
//  NowPlayingInfoManagerTests.swift
//  PlayerHeaderViewTests
//
//  Tests for NowPlayingInfoManager
//

import XCTest
import MediaPlayer
@testable import PlayerHeaderView
@testable import StreamingAudioPlayer

//@MainActor
//final class NowPlayingInfoManagerTests: XCTestCase {
//    
//    var mockPlayer: MockAudioPlayer!
//    var mockSession: MockAudioSession!
//    var mockCommandCenter: MockRemoteCommandCenter!
//    var mockInfoCenter: MockNowPlayingInfoCenter!
//    var controller: AudioPlayerController!
//    var manager: NowPlayingInfoManager!
//    
//    override func setUp() async throws {
//        mockPlayer = MockAudioPlayer()
//        mockSession = MockAudioSession()
//        mockCommandCenter = MockRemoteCommandCenter()
//        mockInfoCenter = MockNowPlayingInfoCenter()
//        
//        controller = AudioPlayerController(
//            player: mockPlayer,
//            audioSession: mockSession,
//            remoteCommandCenter: mockCommandCenter,
//            notificationCenter: .default
//        )
//        
//        manager = NowPlayingInfoManager(controller: controller, infoCenter: mockInfoCenter)
//    }
//    
//    override func tearDown() async throws {
//        manager = nil
//        controller = nil
//        mockPlayer = nil
//        mockSession = nil
//        mockCommandCenter = nil
//        mockInfoCenter = nil
//    }
//    
//    // MARK: - Initialization Tests
//    
//    func testInitialState() {
//        // Manager should start observing immediately
//        // Initial state should reflect controller's isPlaying (false)
//        let expectation = XCTestExpectation(description: "Initial state observed")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            XCTAssertEqual(self.mockInfoCenter.playbackState, .paused)
//            expectation.fulfill()
//        }
//        
//        wait(for: [expectation], timeout: 1.0)
//    }
//    
//    // MARK: - Playback State Tests
//    
//    func testPlaybackStateUpdatesWhenPlaying() {
//        let url = URL(string: "https://example.com/stream")!
//        controller.play(url: url)
//        
//        let expectation = XCTestExpectation(description: "Playback state updated to playing")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//            XCTAssertEqual(self.mockInfoCenter.playbackState, .playing)
//            expectation.fulfill()
//        }
//        
//        wait(for: [expectation], timeout: 1.0)
//    }
//    
//    func testPlaybackStateUpdatesWhenPaused() {
//        let url = URL(string: "https://example.com/stream")!
//        controller.play(url: url)
//        
//        let playExpectation = XCTestExpectation(description: "Playing")
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            self.controller.pause()
//            playExpectation.fulfill()
//        }
//        
//        wait(for: [playExpectation], timeout: 1.0)
//        
//        let pauseExpectation = XCTestExpectation(description: "Paused")
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//            XCTAssertEqual(self.mockInfoCenter.playbackState, .paused)
//            pauseExpectation.fulfill()
//        }
//        
//        wait(for: [pauseExpectation], timeout: 1.0)
//    }
//    
//    // MARK: - Now Playing Info Tests
//    
//    func testNowPlayingInfoInitialized() {
//        let expectation = XCTestExpectation(description: "Now playing info initialized")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            XCTAssertNotNil(self.mockInfoCenter.nowPlayingInfo)
//            expectation.fulfill()
//        }
//        
//        wait(for: [expectation], timeout: 1.0)
//    }
//    
//    func testLiveStreamFlagSet() {
//        let expectation = XCTestExpectation(description: "Live stream flag set")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            let isLiveStream: Bool? = self.mockInfoCenter.getValue(for: MPNowPlayingInfoPropertyIsLiveStream)
//            XCTAssertEqual(isLiveStream, true)
//            expectation.fulfill()
//        }
//        
//        wait(for: [expectation], timeout: 1.0)
//    }
//    
//    func testPlaybackRateUpdates() {
//        let url = URL(string: "https://example.com/stream")!
//        controller.play(url: url)
//        
//        let expectation = XCTestExpectation(description: "Playback rate updated")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
//            let playbackRate: Double? = self.mockInfoCenter.getValue(for: MPNowPlayingInfoPropertyPlaybackRate)
//            XCTAssertEqual(playbackRate, 1.0)
//            expectation.fulfill()
//        }
//        
//        wait(for: [expectation], timeout: 1.0)
//    }
//    
//    // MARK: - Clear Tests
//    
//    func testClear() {
//        let expectation = XCTestExpectation(description: "Info initialized")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//            self.manager.clear()
//            XCTAssertNil(self.mockInfoCenter.nowPlayingInfo)
//            expectation.fulfill()
//        }
//        
//        wait(for: [expectation], timeout: 1.0)
//    }
//}
//
