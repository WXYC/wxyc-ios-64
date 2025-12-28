import Testing
import Foundation
import AVFoundation
@testable import Playback
@testable import PlaybackCore
@testable import AVAudioStreamerModule

@Suite("PlaybackMetrics Tests")
struct PlaybackMetricsTests {
    
    // MARK: - Stalls
    
    // RadioPlayerController stall reporting is now covered by RadioPlayerControllerAnalyticsTests
    // using the new PlaybackAnalytics protocol.

    @Test("AVAudioStreamer reports stall metrics via adapter")
    @MainActor
    func avAudioStreamerStallReporting() async throws {
        let analytics = MockPlaybackAnalytics()
        let url = URL(string: "http://test.com/stream")!

        let adapter = StreamerMetricsAdapter(analytics: analytics)
        let config = AVAudioStreamerConfiguration(url: url)
        let streamer = AVAudioStreamer(configuration: config)
        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        // Recovery event is captured asynchronously on MainActor
        try await Task.sleep(for: .milliseconds(10))

        #expect(analytics.stallRecoveryEvents.count == 1)
        #expect(analytics.stallRecoveryEvents.first?.playerType == .avAudioStreamer)
        #expect(analytics.stallRecoveryEvents.first?.reason == .bufferUnderrun)
    }

    // MARK: - Recoveries

    // RadioPlayerController recovery reporting is now covered by RadioPlayerControllerAnalyticsTests
    // using the new PlaybackAnalytics protocol.

    @Test("AVAudioStreamer reports recovery metrics via adapter")
    @MainActor
    func avAudioStreamerRecoveryReporting() async throws {
        let analytics = MockPlaybackAnalytics()
        let url = URL(string: "http://test.com/stream")!

        let adapter = StreamerMetricsAdapter(analytics: analytics)
        let config = AVAudioStreamerConfiguration(url: url)
        let streamer = AVAudioStreamer(configuration: config)
        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        // Recovery event is captured asynchronously on MainActor
        try await Task.sleep(for: .milliseconds(10))
    
        #expect(analytics.stallRecoveryEvents.count == 1)
        #expect(analytics.stallRecoveryEvents.first?.playerType == .avAudioStreamer)
        #expect(analytics.stallRecoveryEvents.first?.successful == true)
    }

    // MARK: - CPU Usage
        
    @Test("CPUUsageEvent captures player type and usage")
    @MainActor
    func cpuUsageEvent() async throws {
        let analytics = MockPlaybackAnalytics()
        let event = CPUUsageEvent(playerType: .radioPlayer, cpuUsage: 12.5)

        analytics.capture(event)

        #expect(analytics.cpuUsageEvents.count == 1)
        #expect(analytics.cpuUsageEvents.first?.playerType == .radioPlayer)
        #expect(analytics.cpuUsageEvents.first?.cpuUsage == 12.5)
    }

}
