import Testing
import Foundation
@testable import Playback
import AVAudioStreamer
import MiniMP3Streamer

@Suite("StreamerMetricsAdapter Tests")
struct StreamerMetricsAdapterTests {
    
    // Parameterized test for stall reporting
    @Test("Report stall correctly for each player type", arguments: [
        (PlayerControllerType.avAudioStreamer, "http://test.com/av"),
        (PlayerControllerType.miniMP3Streamer, "http://test.com/mp3")
    ])
    @MainActor
    func stallReporting(type: PlayerControllerType, urlString: String) {
        let reporter = MockMetricsReporter()
        let adapter = StreamerMetricsAdapter(reporter: reporter)
        let config = AVAudioStreamerConfiguration(url: URL(string: urlString)!) // Config is compatible
        
        if type == .avAudioStreamer {
            let streamer = AVAudioStreamer(configuration: config)
            adapter.audioStreamerDidStall(streamer)
        } else {
            let config = MiniMP3StreamerConfiguration(url: URL(string: urlString)!)
            let streamer = MiniMP3Streamer(configuration: config)
            adapter.miniMP3StreamerDidStall(streamer)
        }
        
        #expect(reporter.reportedStalls.count == 1)
        #expect(reporter.reportedStalls.first?.playerType == type)
        #expect(reporter.reportedStalls.first?.reason == .bufferUnderrun)
    }
    
    // Parameterized test for recovery reporting
    @Test("Report recovery correctly for each player type", arguments: [
        (PlayerControllerType.avAudioStreamer, "http://test.com/av"),
        (PlayerControllerType.miniMP3Streamer, "http://test.com/mp3")
    ])
    @MainActor
    func recoveryReporting(type: PlayerControllerType, urlString: String) {
        let reporter = MockMetricsReporter()
        let adapter = StreamerMetricsAdapter(reporter: reporter)
        
        if type == .avAudioStreamer {
            let config = AVAudioStreamerConfiguration(url: URL(string: urlString)!)
            let streamer = AVAudioStreamer(configuration: config)
            adapter.audioStreamerDidStall(streamer)
            adapter.audioStreamerDidRecover(streamer)
        } else {
            let config = MiniMP3StreamerConfiguration(url: URL(string: urlString)!)
            let streamer = MiniMP3Streamer(configuration: config)
            adapter.miniMP3StreamerDidStall(streamer)
            adapter.miniMP3StreamerDidRecover(streamer)
        }
        
        #expect(reporter.reportedRecoveries.count == 1)
        #expect(reporter.reportedRecoveries.first?.playerType == type)
        #expect(reporter.reportedRecoveries.first?.successful == true)
        #expect(reporter.reportedRecoveries.first?.recoveryMethod == .bufferRefill)
    }
}
