import Foundation
import AVFoundation
import PostHog
#if !os(watchOS)

final class StreamerMetricsAdapter: @unchecked Sendable, AVAudioStreamerDelegate {
    private let reporter: PlaybackMetricsReporter
    private var stallStartTime: Date?
    
    init(reporter: PlaybackMetricsReporter? = nil) {
        self.reporter = reporter ?? PostHogSDK.shared
    }
    
    // MARK: - AVAudioStreamerDelegate
    
    func audioStreamerDidStall(_ streamer: AVAudioStreamer) {
        handleStall(playerType: .avAudioStreamer)
    }
    
    func audioStreamerDidRecover(_ streamer: AVAudioStreamer) {
        handleRecovery(playerType: .avAudioStreamer)
    }
    
    // MARK: - Helpers
    
    private func handleStall(playerType: PlayerControllerType) {
        stallStartTime = Date()
        let event = StallEvent(
            playerType: playerType,
            timestamp: Date(),
            playbackDuration: 0, // We don't have easy access to duration here without access to the streamer's currentTime
            reason: .bufferUnderrun
        )
        reporter.reportStall(event)
    }
    
    private func handleRecovery(playerType: PlayerControllerType) {
        guard let stallStart = stallStartTime else { return }
        
        let event = RecoveryEvent(
            playerType: playerType,
            successful: true,
            attemptCount: 1,
            stallDuration: Date().timeIntervalSince(stallStart),
            recoveryMethod: .bufferRefill
        )
        reporter.reportRecovery(event)
        stallStartTime = nil
    }
}
#endif
