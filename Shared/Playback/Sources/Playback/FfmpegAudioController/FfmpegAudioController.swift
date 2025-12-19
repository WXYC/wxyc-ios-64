//
//  FfmpegAudioController.swift
//  Playback
//
//  PlaybackController wrapper for the FfmpegAudio StreamPlayer.
//

// Note: Project-level EXCLUDED_ARCHS don't propagate to SPM packages.
// Until we can configure SPM packages to exclude arm64_32, keep os(iOS) check.
#if canImport(FfmpegAudio) && os(iOS)
import Foundation
import AVFoundation
import Observation
import FfmpegAudio

@MainActor
@Observable
final class FfmpegAudioController: PlaybackController {
    
    // MARK: - Public Properties
    
    let streamURL: URL
    
    var isPlaying: Bool {
        player.state == .playing
    }
    
    var isLoading: Bool {
        player.state == .starting
    }
    
    // MARK: - Private Properties
    
    private let player = StreamPlayer()
    // MARK: - Streams
    
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        audioBufferStreamContinuation.0
    }
    
    private let audioBufferStreamContinuation: (AsyncStream<AVAudioPCMBuffer>, AsyncStream<AVAudioPCMBuffer>.Continuation) = {
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingNewest(1)) { c in
            continuation = c
        }
        return (stream, continuation)
    }()
    
    // MARK: - Init
    
    init(streamURL: URL) {
        self.streamURL = streamURL
        // Capture continuation to avoid retaining self strongly in closure if possible,
        // though analysisHandler probably retains self anyway.
        // Actually, we can just use the continuation directly.
        let continuation = audioBufferStreamContinuation.1
        player.analysisHandler = { buffer, _ in
            continuation.yield(buffer)
        }
    }
    
    // MARK: - PlaybackController
    
    func play(reason: String) throws {
        player.start(url: streamURL)
    }
    
    func pause() {
        player.stop()
    }
    
    func toggle(reason: String) throws {
        if isPlaying {
            pause()
        } else {
            try play(reason: reason)
        }
    }
    
    func stop() {
        player.stop()
    }
    
    #if os(iOS)
    func handleAppDidEnterBackground() {
        // Streaming continues if playing; nothing special required when stopped.
    }
    
    func handleAppWillEnterForeground() {
        // No-op; AVAudioEngine resumes as needed.
    }
    #endif
}
#endif
