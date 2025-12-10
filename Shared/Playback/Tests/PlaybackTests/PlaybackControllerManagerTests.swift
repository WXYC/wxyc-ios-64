//
//  PlaybackControllerManagerTests.swift
//  PlaybackTests
//
//  Tests for PlaybackControllerManager - the coordinator that switches between
//  different PlaybackController implementations based on user selection.
//

import Testing
import AVFoundation
@testable import Playback

#if !os(watchOS)

// MARK: - Mock PlaybackController

/// A mock PlaybackController for testing manager behavior
@MainActor
final class MockPlaybackController: PlaybackController, @unchecked Sendable {
    let streamURL: URL
    var _isPlaying = false
    var _isLoading = false
    
    var isPlaying: Bool { _isPlaying }
    var isLoading: Bool { _isLoading }
    
    // Tracking
    var playCallCount = 0
    var pauseCallCount = 0
    var stopCallCount = 0
    var toggleCallCount = 0
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?
    var metadataHandler: (([String: String]) -> Void)?
    var lastPlayReason: String?
    
    #if os(iOS)
    var backgroundCallCount = 0
    var foregroundCallCount = 0
    #endif
    
    init(streamURL: URL = URL(string: "https://test.example.com/stream.mp3")!) {
        self.streamURL = streamURL
    }
    
    func play(reason: String) throws {
        playCallCount += 1
        lastPlayReason = reason
        _isPlaying = true
    }
    
    func pause() {
        pauseCallCount += 1
        _isPlaying = false
    }
    
    func toggle(reason: String) throws {
        toggleCallCount += 1
        if _isPlaying {
            pause()
        } else {
            try play(reason: reason)
        }
    }
    
    func stop() {
        stopCallCount += 1
        _isPlaying = false
    }
    
    func setAudioBufferHandler(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        audioBufferHandler = handler
    }
    
    func setMetadataHandler(_ handler: @escaping ([String: String]) -> Void) {
        metadataHandler = handler
    }
    
    #if os(iOS)
    func handleAppDidEnterBackground() {
        backgroundCallCount += 1
    }
    
    func handleAppWillEnterForeground() {
        foregroundCallCount += 1
    }
    #endif
    
    // Test helpers
    func simulatePlaybackStarted() {
        _isPlaying = true
    }
    
    func simulatePlaybackStopped() {
        _isPlaying = false
    }
    
    func reset() {
        playCallCount = 0
        pauseCallCount = 0
        stopCallCount = 0
        toggleCallCount = 0
        lastPlayReason = nil
        audioBufferHandler = nil
        metadataHandler = nil
        _isPlaying = false
        _isLoading = false
        #if os(iOS)
        backgroundCallCount = 0
        foregroundCallCount = 0
        #endif
    }
}

// MARK: - Test Helpers

/// Creates a mock factory that returns pre-created mock controllers
@MainActor
func createMockFactory(controllers: [PlayerControllerType: MockPlaybackController]) -> PlaybackControllerFactory {
    return { type in
        controllers[type] ?? MockPlaybackController()
    }
}

// MARK: - PlaybackControllerManager Tests

@Suite("PlaybackControllerManager Tests")
@MainActor
struct PlaybackControllerManagerTests {
    
    // MARK: - Initialization Tests
    
    @Test("Manager initializes with provided type")
    func managerInitializesWithProvidedType() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        #expect(manager.currentType == .radioPlayer)
    }
    
    @Test("Manager uses factory to create initial controller")
    func managerUsesFactoryForInitialController() {
        var factoryCallCount = 0
        var factoryCalledWithType: PlayerControllerType?
        
        let factory: PlaybackControllerFactory = { type in
            factoryCallCount += 1
            factoryCalledWithType = type
            return MockPlaybackController()
        }
        
        _ = PlaybackControllerManager(initialType: .avAudioStreamer, factory: factory)
        
        #expect(factoryCallCount == 1)
        #expect(factoryCalledWithType == .avAudioStreamer)
    }
    
    // MARK: - Controller Switching Tests
    
    @Test("switchTo changes currentType")
    func switchToChangesCurrentType() {
        let factory: PlaybackControllerFactory = { _ in MockPlaybackController() }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(manager.currentType == .avAudioStreamer)
    }
    
    @Test("switchTo creates new controller via factory")
    func switchToCreatesNewController() {
        var factoryCalls: [PlayerControllerType] = []
        
        let factory: PlaybackControllerFactory = { type in
            factoryCalls.append(type)
            return MockPlaybackController()
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        factoryCalls.removeAll() // Clear initialization call
        
        manager.switchTo(.miniMP3Streamer)
        
        #expect(factoryCalls == [.miniMP3Streamer])
    }
    
    @Test("switchTo is no-op when switching to same type")
    func switchToSameTypeIsNoOp() {
        var factoryCallCount = 0
        
        let factory: PlaybackControllerFactory = { _ in
            factoryCallCount += 1
            return MockPlaybackController()
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        factoryCallCount = 0 // Reset after init
        
        manager.switchTo(.radioPlayer)
        
        #expect(factoryCallCount == 0, "Should not create new controller when type unchanged")
        #expect(manager.currentType == .radioPlayer)
    }
    
    @Test("switchTo stops current controller before switching")
    func switchToStopsCurrentController() {
        let initialController = MockPlaybackController()
        initialController.simulatePlaybackStarted()
        
        var isFirstCall = true
        let factory: PlaybackControllerFactory = { _ in
            if isFirstCall {
                isFirstCall = false
                return initialController
            }
            return MockPlaybackController()
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        #expect(manager.isPlaying)
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(initialController.stopCallCount == 1, "Should stop the old controller")
    }
    
    @Test("switchTo does not stop if not playing")
    func switchToDoesNotStopIfNotPlaying() {
        let initialController = MockPlaybackController()
        
        var isFirstCall = true
        let factory: PlaybackControllerFactory = { _ in
            if isFirstCall {
                isFirstCall = false
                return initialController
            }
            return MockPlaybackController()
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        #expect(!manager.isPlaying)
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(initialController.stopCallCount == 0, "Should not stop if wasn't playing")
    }
    
    @Test("switchTo resumes playback if was playing")
    func switchToResumesPlaybackIfWasPlaying() {
        let initialController = MockPlaybackController()
        initialController.simulatePlaybackStarted()
        
        let newController = MockPlaybackController()
        
        var isFirstCall = true
        let factory: PlaybackControllerFactory = { _ in
            if isFirstCall {
                isFirstCall = false
                return initialController
            }
            return newController
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        #expect(manager.isPlaying)
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(newController.playCallCount == 1, "Should resume playback on new controller")
        #expect(newController.lastPlayReason == "controller_switch")
    }
    
    @Test("switchTo does not resume if was not playing")
    func switchToDoesNotResumeIfNotPlaying() {
        let newController = MockPlaybackController()
        
        var isFirstCall = true
        let factory: PlaybackControllerFactory = { _ in
            if isFirstCall {
                isFirstCall = false
                return MockPlaybackController()
            }
            return newController
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        #expect(!manager.isPlaying)
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(newController.playCallCount == 0, "Should not resume if wasn't playing")
    }
    
    // MARK: - Handler Transfer Tests
    
    @Test("switchTo transfers audio buffer handler to new controller")
    func switchToTransfersAudioBufferHandler() {
        let newController = MockPlaybackController()
        
        var isFirstCall = true
        let factory: PlaybackControllerFactory = { _ in
            if isFirstCall {
                isFirstCall = false
                return MockPlaybackController()
            }
            return newController
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        var handlerCalled = false
        manager.setAudioBufferHandler { _ in
            handlerCalled = true
        }
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(newController.audioBufferHandler != nil, "Handler should be transferred")
    }
    
    @Test("switchTo transfers metadata handler to new controller")
    func switchToTransfersMetadataHandler() {
        let newController = MockPlaybackController()
        
        var isFirstCall = true
        let factory: PlaybackControllerFactory = { _ in
            if isFirstCall {
                isFirstCall = false
                return MockPlaybackController()
            }
            return newController
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.setMetadataHandler { _ in }
        
        manager.switchTo(.avAudioStreamer)
        
        #expect(newController.metadataHandler != nil, "Handler should be transferred")
    }
    
    // MARK: - Playback Control Tests
    
    @Test("toggle delegates to current controller")
    func toggleDelegatesToController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.toggle()
        
        #expect(mockController.toggleCallCount == 1)
    }
    
    @Test("play delegates to current controller")
    func playDelegatesToController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.play()
        
        #expect(mockController.playCallCount == 1)
    }
    
    @Test("pause delegates to current controller")
    func pauseDelegatesToController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.pause()
        
        #expect(mockController.pauseCallCount == 1)
    }
    
    @Test("stop delegates to current controller")
    func stopDelegatesToController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.stop()
        
        #expect(mockController.stopCallCount == 1)
    }
    
    // MARK: - State Passthrough Tests
    
    @Test("isPlaying reflects current controller state")
    func isPlayingReflectsControllerState() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        #expect(!manager.isPlaying)
        
        mockController.simulatePlaybackStarted()
        #expect(manager.isPlaying)
        
        mockController.simulatePlaybackStopped()
        #expect(!manager.isPlaying)
    }
    
    @Test("isLoading reflects current controller state")
    func isLoadingReflectsControllerState() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        #expect(!manager.isLoading)
        
        mockController._isLoading = true
        #expect(manager.isLoading)
    }
    
    // MARK: - Handler Tests
    
    @Test("setAudioBufferHandler sets on current controller")
    func setAudioBufferHandlerSetsOnController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.setAudioBufferHandler { _ in }
        
        #expect(mockController.audioBufferHandler != nil)
    }
    
    @Test("setMetadataHandler sets on current controller")
    func setMetadataHandlerSetsOnController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.setMetadataHandler { _ in }
        
        #expect(mockController.metadataHandler != nil)
    }
    
    // MARK: - Background/Foreground Tests (iOS)
    
    #if os(iOS)
    @Test("handleAppDidEnterBackground delegates to current controller")
    func handleBackgroundDelegatesToController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.handleAppDidEnterBackground()
        
        #expect(mockController.backgroundCallCount == 1)
    }
    
    @Test("handleAppWillEnterForeground delegates to current controller")
    func handleForegroundDelegatesToController() {
        let mockController = MockPlaybackController()
        let factory: PlaybackControllerFactory = { _ in mockController }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        manager.handleAppWillEnterForeground()
        
        #expect(mockController.foregroundCallCount == 1)
    }
    #endif
    
    // MARK: - Multi-Switch Tests
    
    @Test("Multiple switches update currentType correctly")
    func multipleSwitchesUpdateType() {
        let factory: PlaybackControllerFactory = { _ in MockPlaybackController() }
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        #expect(manager.currentType == .radioPlayer)
        
        manager.switchTo(.avAudioStreamer)
        #expect(manager.currentType == .avAudioStreamer)
        
        manager.switchTo(.miniMP3Streamer)
        #expect(manager.currentType == .miniMP3Streamer)
        
        manager.switchTo(.audioPlayer)
        #expect(manager.currentType == .audioPlayer)
        
        manager.switchTo(.radioPlayer)
        #expect(manager.currentType == .radioPlayer)
    }
    
    @Test("Handlers persist across multiple switches")
    func handlersPersistAcrossSwitches() {
        var createdControllers: [MockPlaybackController] = []
        
        let factory: PlaybackControllerFactory = { _ in
            let controller = MockPlaybackController()
            createdControllers.append(controller)
            return controller
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        var bufferHandlerCallCount = 0
        manager.setAudioBufferHandler { _ in
            bufferHandlerCallCount += 1
        }
        
        // Switch multiple times
        manager.switchTo(.avAudioStreamer)
        manager.switchTo(.miniMP3Streamer)
        manager.switchTo(.audioPlayer)
        
        // All controllers should have received the handler
        for controller in createdControllers {
            #expect(controller.audioBufferHandler != nil, "Each controller should receive the handler")
        }
    }
}

// MARK: - Integration Tests

@Suite("PlaybackControllerManager Integration Tests")
@MainActor
struct PlaybackControllerManagerIntegrationTests {
    
    @Test("Real-world scenario: switch while playing preserves playback")
    func switchWhilePlayingPreservesPlayback() {
        let controller1 = MockPlaybackController()
        let controller2 = MockPlaybackController()
        
        var callIndex = 0
        let factory: PlaybackControllerFactory = { _ in
            callIndex += 1
            return callIndex == 1 ? controller1 : controller2
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        // Start playing
        manager.play()
        controller1.simulatePlaybackStarted()
        #expect(manager.isPlaying)
        
        // Switch controllers
        manager.switchTo(.avAudioStreamer)
        
        // Old controller should be stopped
        #expect(controller1.stopCallCount == 1)
        
        // New controller should be playing
        #expect(controller2.playCallCount == 1)
    }
    
    @Test("Real-world scenario: visualizer handler persists through switches")
    func visualizerHandlerPersistsThroughSwitches() {
        var receivedBuffers: [String] = []
        
        let controllers = [
            PlayerControllerType.radioPlayer: MockPlaybackController(),
            PlayerControllerType.avAudioStreamer: MockPlaybackController(),
        ]
        
        let factory: PlaybackControllerFactory = { type in
            controllers[type]!
        }
        
        let manager = PlaybackControllerManager(initialType: .radioPlayer, factory: factory)
        
        // Set up visualizer handler
        manager.setAudioBufferHandler { _ in
            receivedBuffers.append("buffer")
        }
        
        // Verify handler on first controller
        #expect(controllers[.radioPlayer]!.audioBufferHandler != nil)
        
        // Switch controller
        manager.switchTo(.avAudioStreamer)
        
        // Verify handler transferred to new controller
        #expect(controllers[.avAudioStreamer]!.audioBufferHandler != nil)
    }
}

#endif // !os(watchOS)
