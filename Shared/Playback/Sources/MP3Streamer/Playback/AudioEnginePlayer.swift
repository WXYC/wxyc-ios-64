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
import Core
import Logger
import os.lock
import Analytics
import PlaybackCore

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
    /// The `AVAudioUnitEQ.globalGain` range, in decibels.
    private static let minGainDecibels: Float = -96
    private static let maxGainDecibels: Float = 24

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    /// Output gain stage inserted between the player node and the main mixer.
    /// Uses only `globalGain` (no bands) to apply a flat decibel boost/cut.
    private let gainNode: AVAudioUnitEQ
    /// Clamped source of truth for `gainDecibels`, mirrored onto `gainNode.globalGain`.
    private var _gainDecibels: Float = 0
    private let format: AVAudioFormat
    private let stateBox: PlayerStateBox
    private let schedulingQueue: DispatchQueue
    private let analytics: AnalyticsService?

    // Track scheduled buffers to know when to request more
    private let scheduledBufferCount: ScheduledBufferCount

    // Event stream - bounded to prevent unbounded growth
    let eventStream: AsyncStream<AudioPlayerEvent>
    private let eventContinuation: AsyncStream<AudioPlayerEvent>.Continuation

    /// Relay that manages mutable render tap continuations, allowing fresh streams
    /// to be created across play sessions without the single-use AsyncStream limitation.
    private let renderTapRelay = RenderTapRelay()

    /// Tracks whether the render tap is currently installed
    private let renderTapState: RenderTapState

    /// Tracks whether the audio engine has been set up (deferred until first play)
    private let engineSetUpState: EngineSetUpState
    
    /// Tracks whether render tap installation was requested before engine setup
    private let pendingRenderTapState: RenderTapState

    /// Task observing engine configuration changes (route changes, etc.)
    private var configurationObserverTask: Task<Void, Never>?

    var isPlaying: Bool {
        stateBox.isPlaying
    }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    /// Output gain applied after the player node, in decibels. Backed by
    /// `gainNode.globalGain`. `0` (the default) is unity — no boost or cut.
    /// Clamped to the unit's valid range (-96...24 dB). The value is stored so
    /// it round-trips before the engine graph is built, and is re-applied to the
    /// node whenever the graph is (re)connected.
    var gainDecibels: Float {
        get { _gainDecibels }
        set {
            let clamped = min(max(newValue, Self.minGainDecibels), Self.maxGainDecibels)
            _gainDecibels = clamped
            gainNode.globalGain = clamped
        }
    }

    init(format: AVAudioFormat, analytics: AnalyticsService? = nil) {
        self.format = format
        self.analytics = analytics
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.gainNode = AVAudioUnitEQ(numberOfBands: 0)
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

        // NOTE: We intentionally do NOT call setUpAudioEngine() here.
        // Accessing engine.mainMixerNode during init implicitly activates the audio
        // hardware and interrupts other apps' audio. Setup is deferred until play().
    }
        
    /// Sets up the audio engine graph. Called lazily on first play() to avoid
    /// interrupting other apps' audio during app launch.
    private func setUpAudioEngineIfNeeded() {
        guard engineSetUpState.setUpIfNeeded() else { return } // Already set up

        // Graph: playerNode -> gainNode (globalGain) -> mainMixerNode.
        // The render tap stays on playerNode (pre-gain), so the visualizer is
        // unaffected by the output boost.
        engine.attach(playerNode)
        engine.attach(gainNode)
        engine.connect(playerNode, to: gainNode, format: format)
        engine.connect(gainNode, to: engine.mainMixerNode, format: format)
        gainNode.globalGain = _gainDecibels

        // Install any pending render tap that was requested before engine was ready
        if pendingRenderTapState.remove() {
            guard renderTapState.install() else { return }
            let relay = renderTapRelay
            playerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                relay.yield(buffer)
            }
        }

        // Observe engine configuration changes (audio route changes, etc.)
        // When the hardware configuration changes, the engine stops and must be restarted
        setUpConfigurationChangeObserver()
    }

    private func setUpConfigurationChangeObserver() {
        configurationObserverTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .AVAudioEngineConfigurationChange,
                object: self?.engine
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { break }
                self.handleConfigurationChange()
            }
        }
    }

    private func handleConfigurationChange() {
        // Engine has stopped due to configuration change (route change, etc.)
        guard stateBox.isPlaying else { return }

        do {
            // Reconnect the audio graph - configuration change may have invalidated it
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(gainNode)
            engine.connect(playerNode, to: gainNode, format: format)
            engine.connect(gainNode, to: engine.mainMixerNode, format: format)
            gainNode.globalGain = _gainDecibels

            try engine.start()
            playerNode.play()
            Log(.info, category: .playback, "Audio engine restarted after configuration change")
        } catch {
            Log(.error, category: .playback, "Failed to restart engine after configuration change: \(error)")
            eventContinuation.yield(.error(error))
        }
    }

    // MARK: - Render Tap Management

    func installRenderTap() {
        // If engine isn't set up yet, just mark that we want a render tap.
        // The tap will be installed when play() triggers engine setup.
        // This avoids interrupting other apps' audio on launch.
        guard engineSetUpState.isSetUp else {
            Log(.debug, category: .playback, "Render tap install deferred (engine not ready)")
            _ = pendingRenderTapState.install()
            return
        }

        guard renderTapState.install() else { return } // Already installed

        Log(.info, category: .playback, "Render tap installed")
        let relay = renderTapRelay
        playerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            relay.yield(buffer)
        }
    }

    func removeRenderTap() {
        guard renderTapState.remove() else { return } // Already removed

        Log(.info, category: .playback, "Render tap removed")
        playerNode.removeTap(onBus: 0)
    }

    func makeRenderTapStream() -> AsyncStream<AVAudioPCMBuffer> {
        renderTapRelay.makeStream()
    }

    func play() throws {
        if stateBox.isPlaying {
            analytics?.capture(PlaybackStartedEvent(reason: "audioEnginePlayer already playing"))
            return
        }

        Log(.info, category: .playback, "Audio engine play requested")
        analytics?.capture(PlaybackStartedEvent(reason: "audioEnginePlayer play"))

        // Defer audio engine setup until first play to avoid interrupting other apps on launch
        setUpAudioEngineIfNeeded()

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Log(.error, category: .playback, "Engine start failed: \(error)")
                tearDownEngine()
                throw error
            }
            Log(.info, category: .playback, "Audio engine started")
        }

        playerNode.play()
        stateBox.isPlaying = true
        eventContinuation.yield(.started)
    }

    func pause() {
        guard stateBox.isPlaying else { return }

        Log(.info, category: .playback, "Audio engine paused")
        analytics?.capture(PlaybackStoppedEvent(reason: "audioEnginePlayer pause", duration: 0)) // Duration 0 as we don't track it here yet
        playerNode.pause()
        stateBox.isPlaying = false
        eventContinuation.yield(.paused)
    }

    func stop() {
        guard stateBox.isPlaying || engine.isRunning else { return }

        Log(.info, category: .playback, "Audio engine stopped")
        analytics?.capture(PlaybackStoppedEvent(reason: "audioEnginePlayer stop", duration: 0))

        // Set isPlaying false first so in-flight scheduling blocks see it immediately
        // via their isPlaying check and exit early.
        stateBox.isPlaying = false

        // Dispatch the full teardown sequence asynchronously to avoid blocking the
        // caller (often the main thread). The ordering guarantee is preserved: in-flight
        // scheduling blocks complete first (they're ahead in the serial queue), then
        // playerNode.stop() clears buffers, then the engine stops.
        //
        // Previously this used schedulingQueue.sync, which blocked the main thread
        // for the duration of any in-flight buffer scheduling — the same class of
        // deadlock as the MP3StreamDecoder.reset() issue (0x8BADF00D watchdog kill).
        schedulingQueue.async { [self] in
            playerNode.stop()
            engine.stop()
            scheduledBufferCount.reset()
            eventContinuation.yield(.stopped)
        }
    }

    /// Tears down the audio engine graph so it can be rebuilt on the next `play()` call.
    /// Called when `engine.start()` fails to ensure the engine isn't permanently stuck.
    func tearDownEngine() {
        configurationObserverTask?.cancel()
        configurationObserverTask = nil

        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(gainNode)
        engine.detach(playerNode)
        engine.detach(gainNode)

        // Detaching the player node physically removes any installed tap.
        // Reset renderTapState to match, and if a tap was installed, mark it
        // as pending so it gets re-installed on the next engine setup.
        if renderTapState.remove() {
            _ = pendingRenderTapState.install()
        }

        engineSetUpState.reset()
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        scheduleBuffers([buffer])
    }

    func scheduleBuffers(_ buffers: [AVAudioPCMBuffer]) {
        guard !buffers.isEmpty else { return }

        schedulingQueue.async { [weak self] in
            guard let self else { return }
            guard self.stateBox.isPlaying else { return }

            // If we were stalled and now have buffers, we're recovering
            // Uses atomic check-and-clear to avoid redundant lock acquisitions
            if self.stateBox.clearStalledIfSet() {
                Log(.info, category: .playback, "Recovered from buffer underrun")
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
                            Log(.warning, category: .playback, "Buffer underrun detected (stalled)")
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

    /// Resets the engine setup state so the engine will be set up again on next use.
    func reset() {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        _isSetUp = false
    }
}

/// Manages a mutable AsyncStream continuation for the render tap, allowing
/// fresh streams to be created across play sessions. AsyncStream is single-use:
/// once a consumer's iterator is deallocated, the stream terminates permanently.
/// This relay solves the problem by finishing the old continuation and creating
/// a new stream+continuation pair on each `makeStream()` call.
private final class RenderTapRelay: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var _continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Creates a fresh AsyncStream, finishing any previously active continuation.
    func makeStream() -> AsyncStream<AVAudioPCMBuffer> {
        os_unfair_lock_lock(lock)
        let old = _continuation
        var newCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingNewest(1)) { newCont = $0 }
        _continuation = newCont
        os_unfair_lock_unlock(lock)
        old?.finish()
        return stream
    }

    /// Yields a buffer to the current continuation, if any.
    /// The lock protects only the pointer read; the actual yield happens outside
    /// the lock to keep the critical section minimal for the audio thread.
    func yield(_ buffer: AVAudioPCMBuffer) {
        os_unfair_lock_lock(lock)
        let cont = _continuation
        os_unfair_lock_unlock(lock)
        cont?.yield(buffer)
    }
}

#endif
