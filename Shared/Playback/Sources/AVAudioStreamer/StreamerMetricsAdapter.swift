import Foundation
import AVFoundation
import PlaybackCore
#if !os(watchOS)

public final class StreamerMetricsAdapter: @unchecked Sendable, AVAudioStreamerDelegate {
    private let analytics: PlaybackAnalytics
    private var stallStartTime: Date?
    private var attemptCount: Int = 0

    public init(analytics: PlaybackAnalytics) {
        self.analytics = analytics
    }

    // MARK: - AVAudioStreamerDelegate

    public func audioStreamerDidStall(_ streamer: AVAudioStreamer) {
        stallStartTime = Date()
        attemptCount += 1
    }

    public func audioStreamerDidRecover(_ streamer: AVAudioStreamer) {
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
