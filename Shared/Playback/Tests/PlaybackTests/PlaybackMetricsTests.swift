import Testing
import Foundation
import AVFoundation
@testable import Playback
@testable import PlaybackCore

@Suite("PlaybackMetrics Tests")
struct PlaybackMetricsTests {
    
    // MARK: - Stalls
    
    // RadioPlayerController stall reporting is now covered by RadioPlayerControllerAnalyticsTests
    // using the new PlaybackAnalytics protocol.

    @Test("AVAudioStreamer reports stall metrics via adapter")
    @MainActor
    func avAudioStreamerStallReporting() async throws {
        let reporter = MockMetricsReporter()
        let url = URL(string: "http://test.com/stream")!

        let adapter = StreamerMetricsAdapter(reporter: reporter)
        let config = AVAudioStreamerConfiguration(url: url)
        let streamer = AVAudioStreamer(configuration: config)
        adapter.audioStreamerDidStall(streamer)

        #expect(reporter.reportedStalls.count == 1)
        #expect(reporter.reportedStalls.first?.playerType == .avAudioStreamer)
        #expect(reporter.reportedStalls.first?.reason == .bufferUnderrun)
    }

    // MARK: - Recoveries
            
    // RadioPlayerController recovery reporting is now covered by RadioPlayerControllerAnalyticsTests
    // using the new PlaybackAnalytics protocol.

    @Test("AVAudioStreamer reports recovery metrics via adapter")
    @MainActor
    func avAudioStreamerRecoveryReporting() async throws {
        let reporter = MockMetricsReporter()
        let url = URL(string: "http://test.com/stream")!

        let adapter = StreamerMetricsAdapter(reporter: reporter)
        let config = AVAudioStreamerConfiguration(url: url)
        let streamer = AVAudioStreamer(configuration: config)
        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        #expect(reporter.reportedRecoveries.count == 1)
        #expect(reporter.reportedRecoveries.first?.playerType == .avAudioStreamer)
        #expect(reporter.reportedRecoveries.first?.successful == true)
    }
    
    // MARK: - CPU Usage
    
    @Test("Monitoring CPU usage reports events")
    @MainActor
    func cpuUsageReporting() async throws {
        // Since CPUMonitor is internal to PlaybackControllerManager and runs on a timer,
        // it's hard to deterministically test the loop in a unit test without exposing internals.
        // However, we can verify the Event struct and Reporter integration.
        
        let reporter = MockMetricsReporter()
        let event = CPUUsageEvent(playerType: .radioPlayer, cpuUsage: 12.5)
        
        reporter.reportCPUUsage(event)
        
        #expect(reporter.reportedCPUUsages.first?.cpuUsage == 12.5)
        #expect(reporter.reportedCPUUsages.first?.properties["cpu_usage"] as? Double == 12.5)
    }
            

}
