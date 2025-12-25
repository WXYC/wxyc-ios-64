import Testing
import Foundation
@testable import Playback
import AVAudioStreamer

@Suite("StreamerMetricsAdapter Tests")
struct StreamerMetricsAdapterTests {

    @Test("Report stall correctly for AVAudioStreamer")
    @MainActor
    func stallReporting() {
        let reporter = MockMetricsReporter()
        let adapter = StreamerMetricsAdapter(reporter: reporter)
        let config = AVAudioStreamerConfiguration(url: URL(string: "http://test.com/stream")!)
        let streamer = AVAudioStreamer(configuration: config)

        adapter.audioStreamerDidStall(streamer)

        #expect(reporter.reportedStalls.count == 1)
        #expect(reporter.reportedStalls.first?.playerType == .avAudioStreamer)
        #expect(reporter.reportedStalls.first?.reason == .bufferUnderrun)
    }

    @Test("Report recovery correctly for AVAudioStreamer")
    @MainActor
    func recoveryReporting() {
        let reporter = MockMetricsReporter()
        let adapter = StreamerMetricsAdapter(reporter: reporter)
        let config = AVAudioStreamerConfiguration(url: URL(string: "http://test.com/stream")!)
        let streamer = AVAudioStreamer(configuration: config)

        adapter.audioStreamerDidStall(streamer)
        adapter.audioStreamerDidRecover(streamer)

        #expect(reporter.reportedRecoveries.count == 1)
        #expect(reporter.reportedRecoveries.first?.playerType == .avAudioStreamer)
        #expect(reporter.reportedRecoveries.first?.successful == true)
        #expect(reporter.reportedRecoveries.first?.recoveryMethod == .bufferRefill)
    }
}
