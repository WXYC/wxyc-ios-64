import Testing
import Foundation
@testable import AVAudioStreamerModule
@testable import PlaybackCore

@Suite("StreamerMetricsAdapter Tests")
struct StreamerMetricsAdapterTests {

    @Test("Report stall correctly for AVAudioStreamer")
    @MainActor
    func stallReporting() async throws {
        let analytics = MockPlaybackAnalytics()
        let adapter = StreamerMetricsAdapter(analytics: analytics)
        let config = AVAudioStreamerConfiguration(url: URL(string: "http://test.com/stream")!)
        let streamer = AVAudioStreamer(configuration: config)

        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        // Recovery event is captured asynchronously on MainActor
        try await Task.sleep(for: .milliseconds(10))

        #expect(analytics.stallRecoveryEvents.count == 1)
        #expect(analytics.stallRecoveryEvents.first?.playerType == .avAudioStreamer)
        #expect(analytics.stallRecoveryEvents.first?.reason == .bufferUnderrun)
    }

    @Test("Report recovery correctly for AVAudioStreamer")
    @MainActor
    func recoveryReporting() async throws {
        let analytics = MockPlaybackAnalytics()
        let adapter = StreamerMetricsAdapter(analytics: analytics)
        let config = AVAudioStreamerConfiguration(url: URL(string: "http://test.com/stream")!)
        let streamer = AVAudioStreamer(configuration: config)

        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        // Recovery event is captured asynchronously on MainActor
        try await Task.sleep(for: .milliseconds(10))

        #expect(analytics.stallRecoveryEvents.count == 1)
        #expect(analytics.stallRecoveryEvents.first?.playerType == .avAudioStreamer)
        #expect(analytics.stallRecoveryEvents.first?.successful == true)
        #expect(analytics.stallRecoveryEvents.first?.recoveryMethod == .bufferRefill)
    }

    @Test("Multiple stalls increment attempt count")
    @MainActor
    func multipleStallsIncrementAttempts() async throws {
        let analytics = MockPlaybackAnalytics()
        let adapter = StreamerMetricsAdapter(analytics: analytics)
        let config = AVAudioStreamerConfiguration(url: URL(string: "http://test.com/stream")!)
        let streamer = AVAudioStreamer(configuration: config)

        // Simulate multiple stalls before recovery
        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        try await Task.sleep(for: .milliseconds(10))

        #expect(analytics.stallRecoveryEvents.count == 1)
        #expect(analytics.stallRecoveryEvents.first?.attempts == 3)
    }
}
