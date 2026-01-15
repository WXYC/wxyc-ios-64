//
//  AudioEnginePlayer.swift
//  Playback
//
//  AVAudioEngine-based audio playback with buffer scheduling.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#if !os(watchOS)

@preconcurrency import AVFoundation
import os.lock
import Analytics

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Errors that can occur during audio playback
enum AudioPlayerError: Error {
    case engineStartFailed
    case invalidFormat
    case bufferSchedulingFailed
}

/// Manages audio playback using AVAudioEngine
final class AudioEnginePlayer: AudioEnginePlayerProtocol, @unchecked Sendable {
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let format: AVAudioFormat
    private let stateBox: PlayerStateBox
    private let schedulingQueue: DispatchQueue
    private let analytics: AnalyticsService?

    // Track scheduled buffers to know when to request more
    private let scheduledBufferCount: ScheduledBufferCount

    // Event stream - bounded to prevent unbounded growth
    let eventStream: AsyncStream<AudioPlayerEvent>
    private let eventContinuation: AsyncStream<AudioPlayerEvent>.Continuation

    /// Stream of audio buffers from the render tap.
    /// Only yields buffers when tap is installed via `installRenderTap()`.
    let renderTapStream: AsyncStream<AVAudioPCMBuffer>
    private let renderTapContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    /// Tracks whether the render tap is currently installed
    private let renderTapState: RenderTapState

    /// Tracks whether the audio engine has been set up (deferred until first play)
    private let engineSetUpState: EngineSetUpState
    
    /// Tracks whether render tap installation was requested before engine setup
    private let pendingRenderTapState: RenderTapState

    var isPlaying: Bool {
        stateBox.isPlaying
    }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    init(format: AVAudioFormat, analytics: AnalyticsService? = nil) {
        self.format = format
        self.analytics = analytics
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.stateBox = PlayerStateBox()
        self.scheduledBufferCount = ScheduledBufferCount()
        self.schedulingQueue = DispatchQueue(label: "com.avaudiostreamer.scheduling", qos: .userInitiated)
        self.renderTapState = RenderTapState()
        self.engineSetUpState = EngineSetUpState()
        self.pendingRenderTapState = RenderTapState()

        // Initialize event stream with bounded buffer to prevent unbounded growth
        var eventCont: AsyncStream<AudioPlayerEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { eventCont = $0 }
        self.eventContinuation = eventCont

        // Initialize render tap stream - only keeps latest buffer for visualization
        var renderCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.renderTapStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { renderCont = $0 }
        self.renderTapContinuation = renderCont

        // NOTE: We intentionally do NOT call setUpAudioEngine() here.
        // Accessing engine.mainMixerNode during init implicitly activates the audio
        // hardware and interrupts other apps' audio. Setup is deferred until play().
    }

    /// Sets up the audio engine graph. Called lazily on first play() to avoid
    /// interrupting other apps' audio during app launch.
    private func setUpAudioEngineIfNeeded() {
        guard engineSetUpState.setUpIfNeeded() else { return } // Already set up
        
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        // Install any pending render tap that was requested before engine was ready
        if pendingRenderTapState.remove() {
            guard renderTapState.install() else { return }
            let continuation = renderTapContinuation
            playerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                continuation.yield(buffer)
            }
        }
    }

    // MARK: - Render Tap Management

    func installRenderTap() {
        // If engine isn't set up yet, just mark that we want a render tap.
        // The tap will be installed when play() triggers engine setup.
        // This avoids interrupting other apps' audio on launch.
        guard engineSetUpState.isSetUp else {
            _ = pendingRenderTapState.install()
            return
        }
        
        guard renderTapState.install() else { return } // Already installed
        
        let continuation = renderTapContinuation
        playerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            continuation.yield(buffer)
        }
    }

    func removeRenderTap() {
        guard renderTapState.remove() else { return } // Already removed

        playerNode.removeTap(onBus: 0)
    }
        
    func play() throws {
        if stateBox.isPlaying {
            analytics?.capture("audioEnginePlayer already playing")
            return
        }
        
        analytics?.capture("audioEnginePlayer play")
        
        // Defer audio engine setup until first play to avoid interrupting other apps on launch
        setUpAudioEngineIfNeeded()
        
        if !engine.isRunning {
            try engine.start()
        }

        playerNode.play()
        stateBox.isPlaying = true
        eventContinuation.yield(.started)
    }

    func pause() {
        guard stateBox.isPlaying else { return }

        analytics?.capture("audioEnginePlayer pause")
        playerNode.pause()
        stateBox.isPlaying = false
        eventContinuation.yield(.paused)
    }

    func stop() {
        guard stateBox.isPlaying || engine.isRunning else { return }

        analytics?.capture("audioEnginePlayer stop")
        playerNode.stop()
        engine.stop()
        stateBox.isPlaying = false
        scheduledBufferCount.reset()
        eventContinuation.yield(.stopped)
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        scheduleBuffers([buffer])
    }

    func scheduleBuffers(_ buffers: [AVAudioPCMBuffer]) {
        guard !buffers.isEmpty else { return }

        schedulingQueue.async { [weak self] in
            guard let self else { return }

            // If we were stalled and now have buffers, we're recovering
            // Uses atomic check-and-clear to avoid redundant lock acquisitions
            if self.stateBox.clearStalledIfSet() {
                self.eventContinuation.yield(.recoveredFromStall)
            }

            // Schedule all buffers in a single dispatch for efficiency
            for buffer in buffers {
                self.playerNode.scheduleBuffer(buffer) { [weak self] in
                    guard let self else { return }

                    // Buffer finished playing - get count after decrement in single lock acquisition
                    let count = self.scheduledBufferCount.decrementAndGet()

                    // Get playing state once to avoid redundant lock acquisitions
                    let isPlaying = self.stateBox.isPlaying

                    // Detect stall: count hit zero while we were playing
                    if count == 0 && isPlaying {
                        if self.stateBox.setStalledIfPlaying() {
                            self.eventContinuation.yield(.stalled)
                        }
                    }

                    // Request more buffers if running low
                    if count < 3 && isPlaying {
                        self.eventContinuation.yield(.needsMoreBuffers)
                    }
                }
            }

            // Batch increment: single lock acquisition for all buffers
            self.scheduledBufferCount.incrementBy(buffers.count)
        }
    }
}

// MARK: - Thread-safe state management

private final class PlayerStateBox: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var _isPlaying = false
    private var _isStalled = false

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var isPlaying: Bool {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _isPlaying
        }
        set {
            os_unfair_lock_lock(lock)
            _isPlaying = newValue
            os_unfair_lock_unlock(lock)
        }
    }

    var isStalled: Bool {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _isStalled
        }
        set {
            os_unfair_lock_lock(lock)
            _isStalled = newValue
            os_unfair_lock_unlock(lock)
        }
    }

    /// Atomically clears the stalled flag if it was set.
    /// Returns true if stalled was true and is now false.
    func clearStalledIfSet() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if _isStalled {
            _isStalled = false
            return true
        }
        return false
    }

    /// Atomically sets the stalled flag if currently playing.
    /// Returns true if stalled was set.
    func setStalledIfPlaying() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if _isPlaying && !_isStalled {
            _isStalled = true
            return true
        }
        return false
    }

}

private final class ScheduledBufferCount: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var _count = 0

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Increments the count by the specified amount in a single lock acquisition.
    func incrementBy(_ amount: Int) {
        os_unfair_lock_lock(lock)
        _count += amount
        os_unfair_lock_unlock(lock)
    }

    /// Decrements the count and returns the new value in a single lock acquisition.
    func decrementAndGet() -> Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        _count = max(0, _count - 1)
        return _count
    }

    func reset() {
        os_unfair_lock_lock(lock)
        _count = 0
        os_unfair_lock_unlock(lock)
    }
}

/// Thread-safe state for render tap installation
private final class RenderTapState: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var _isInstalled = false

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Attempts to install the tap. Returns true if the tap was not already installed.
    func install() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if _isInstalled { return false }
        _isInstalled = true
        return true
    }

    /// Attempts to remove the tap. Returns true if the tap was installed.
    func remove() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if !_isInstalled { return false }
        _isInstalled = false
        return true
    }
}

/// Thread-safe state for deferred engine setup
private final class EngineSetUpState: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var _isSetUp = false

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Whether the engine has been set up
    var isSetUp: Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _isSetUp
    }

    /// Attempts to mark the engine as set up. Returns true if this is the first call.
    func setUpIfNeeded() -> Bool {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if _isSetUp { return false }
        _isSetUp = true
        return true
    }
}

#endif
