import Foundation
import AVFoundation
import PlaybackCore
#if !os(watchOS)

final class StreamerMetricsAdapter: @unchecked Sendable, AVAudioStreamerDelegate {
    private let analytics: PlaybackAnalytics
    private var stallStartTime: Date?
    private var attemptCount: Int = 0

    init(analytics: PlaybackAnalytics) {
        self.analytics = analytics
    }

    // MARK: - AVAudioStreamerDelegate

    func audioStreamerDidStall(_ streamer: AVAudioStreamer) {
        stallStartTime = Date()
        attemptCount += 1
    }

    func audioStreamerDidRecover(_ streamer: AVAudioStreamer) {
        guard let stallStart = stallStartTime else { return }

        let event = StallRecoveryEvent(
            playerType: .avAudioStreamer,
            successful: true,
            attempts: attemptCount,
            stallDuration: Date().timeIntervalSince(stallStart),
            reason: .bufferUnderrun,
            recoveryMethod: .bufferRefill
        )

        Task { @MainActor [analytics] in
            analytics.capture(event)
        }

        stallStartTime = nil
        attemptCount = 0
    }
}
#endif
