#if !os(watchOS)

@preconcurrency import AVFoundation

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
final class AudioEnginePlayer: @unchecked Sendable {
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let format: AVAudioFormat
    private let stateBox: PlayerStateBox
    private weak var delegate: (any AudioPlayerDelegate)?
    private let schedulingQueue: DispatchQueue

    // Track scheduled buffers to know when to request more
    private let scheduledBufferCount: ScheduledBufferCount

    /// Stream of audio buffers from the render tap - yields at render rate (~60 times/sec)
    let renderTapStream: AsyncStream<AVAudioPCMBuffer>
    private let renderTapContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    var isPlaying: Bool {
        stateBox.isPlaying
    }

    var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = newValue }
    }

    init(format: AVAudioFormat, delegate: any AudioPlayerDelegate) {
        self.format = format
        self.delegate = delegate
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.stateBox = PlayerStateBox()
        self.scheduledBufferCount = ScheduledBufferCount()
        self.schedulingQueue = DispatchQueue(label: "com.avaudiostreamer.scheduling", qos: .userInitiated)

        // Initialize render tap stream
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.renderTapStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { c in
            continuation = c
        }
        self.renderTapContinuation = continuation

        setUpAudioEngine()
    }

    private func setUpAudioEngine() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        // Install tap on main mixer to capture audio at render rate
        // Use the player's format (44.1kHz) to match FFT processor expectations
        let continuation = renderTapContinuation
        playerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            continuation.yield(buffer)
        }

        engine.prepare()
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

        notifyDelegate { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioPlayerDidStartPlaying(self)
        }
    }

    func pause() {
        guard stateBox.isPlaying else { return }

        playerNode.pause()
        stateBox.isPlaying = false

        notifyDelegate { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioPlayerDidPause(self)
        }
    }

    func stop() {
        guard stateBox.isPlaying || engine.isRunning else { return }

        playerNode.stop()
        engine.stop()
        stateBox.isPlaying = false
        scheduledBufferCount.reset()

        notifyDelegate { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioPlayerDidStop(self)
        }
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        schedulingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // If we were stalled and now have a buffer, we're recovering
            if self.stateBox.isStalled {
                self.stateBox.isStalled = false
                self.notifyDelegate { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.audioPlayerDidRecoverFromStall(self)
                }
            }

            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                guard let self = self else { return }

                // Buffer finished playing
                self.scheduledBufferCount.decrement()
                
                // Detect stall: count hit zero while we were playing
                if self.scheduledBufferCount.count == 0 && self.stateBox.isPlaying {
                    self.stateBox.isStalled = true
                    self.notifyDelegate { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.audioPlayerDidStall(self)
                    }
                }

                // Request more buffers if running low
                if self.scheduledBufferCount.count < 3 && self.stateBox.isPlaying {
                    self.notifyDelegate { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.audioPlayerNeedsMoreBuffers(self)
                    }
                }
            }

            self.scheduledBufferCount.increment()
        }
    }

    private func notifyDelegate(_ closure: @Sendable @escaping () -> Void) {
        Task { @MainActor in
            closure()
        }
    }
}

// MARK: - Thread-safe state management

private final class PlayerStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _isPlaying = false

    var isPlaying: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isPlaying
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isPlaying = newValue
        }
    }

    var isStalled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isStalled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isStalled = newValue
        }
    }
    
    private var _isStalled = false
}

private final class ScheduledBufferCount: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }

    func decrement() {
        lock.lock()
        defer { lock.unlock() }
        _count = max(0, _count - 1)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _count = 0
    }
}

#endif
