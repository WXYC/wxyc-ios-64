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
    private var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?
    
    // MARK: - Init
    
    init(streamURL: URL) {
        self.streamURL = streamURL
        player.analysisHandler = { [weak self] buffer, _ in
            guard let handler = self?.audioBufferHandler else { return }
            handler(buffer)
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
    
    func setAudioBufferHandler(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        audioBufferHandler = handler
    }
    
    func setMetadataHandler(_ handler: @escaping ([String: String]) -> Void) {
        // FFmpeg path does not currently surface metadata.
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
