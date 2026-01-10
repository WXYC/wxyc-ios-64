#if !os(watchOS)

@preconcurrency import AVFoundation
import os.lock

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// Errors that can occur during audio playback
enum AudioPlayerError: Error {
    case engineStartFailed
    case audioSessionSetupFailed
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

    var isPlaying: Bool {
        stateBox.isPlaying
    }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    init(format: AVAudioFormat) {
        self.format = format
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.stateBox = PlayerStateBox()
        self.scheduledBufferCount = ScheduledBufferCount()
        self.schedulingQueue = DispatchQueue(label: "com.avaudiostreamer.scheduling", qos: .userInitiated)
        self.renderTapState = RenderTapState()

        // Initialize event stream with bounded buffer to prevent unbounded growth
        var eventCont: AsyncStream<AudioPlayerEvent>.Continuation!
        self.eventStream = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { eventCont = $0 }
        self.eventContinuation = eventCont

        // Initialize render tap stream - only keeps latest buffer for visualization
        var renderCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.renderTapStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { renderCont = $0 }
        self.renderTapContinuation = renderCont

        setUpAudioEngine()
    }

    private func setUpAudioEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        // Note: Render tap is NOT installed by default - call installRenderTap() when needed
        engine.prepare()
    }

    // MARK: - Render Tap Management

    func installRenderTap() {
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

    func setUpAudioSession() throws {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            throw AudioPlayerError.audioSessionSetupFailed
        }
        #endif
    }

    func play() throws {
        guard !stateBox.isPlaying else { return }

        try setUpAudioSession()

        if !engine.isRunning {
            try engine.start()
        }

        playerNode.play()
        stateBox.isPlaying = true
        eventContinuation.yield(.started)
    }

    func pause() {
        guard stateBox.isPlaying else { return }

        playerNode.pause()
        stateBox.isPlaying = false
        eventContinuation.yield(.paused)
    }

    func stop() {
        guard stateBox.isPlaying || engine.isRunning else { return }

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
            if self.stateBox.isStalled {
                self.stateBox.isStalled = false
                self.eventContinuation.yield(.recoveredFromStall)
            }

            // Schedule all buffers in a single dispatch for efficiency
            for buffer in buffers {
                self.playerNode.scheduleBuffer(buffer) { [weak self] in
                    guard let self else { return }

                    // Buffer finished playing
                    self.scheduledBufferCount.decrement()

                    // Detect stall: count hit zero while we were playing
                    if self.scheduledBufferCount.count == 0 && self.stateBox.isPlaying {
                        self.stateBox.isStalled = true
                        self.eventContinuation.yield(.stalled)
                    }

                    // Request more buffers if running low
                    if self.scheduledBufferCount.count < 3 && self.stateBox.isPlaying {
                        self.eventContinuation.yield(.needsMoreBuffers)
                    }
                }

                self.scheduledBufferCount.increment()
            }
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

    var count: Int {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _count
    }

    func increment() {
        os_unfair_lock_lock(lock)
        _count += 1
        os_unfair_lock_unlock(lock)
    }

    func decrement() {
        os_unfair_lock_lock(lock)
        _count = max(0, _count - 1)
        os_unfair_lock_unlock(lock)
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

#endif
