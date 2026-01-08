import Testing
import Foundation
import AVFoundation
@testable import Playback
@testable import PlaybackCore

@Suite("PlaybackMetrics Tests")
struct PlaybackMetricsTests {

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
