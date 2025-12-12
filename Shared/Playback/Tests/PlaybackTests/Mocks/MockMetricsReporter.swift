import Foundation
@testable import Playback

final class MockMetricsReporter: PlaybackMetricsReporter, @unchecked Sendable {
    var reportedStalls: [StallEvent] = []
    var reportedRecoveries: [RecoveryEvent] = []
    var reportedErrors: [PlaybackErrorEvent] = []
    var reportedCPUUsages: [CPUUsageEvent] = [] // Make this publicly readable for tests
    
    func reportStall(_ event: StallEvent) {
        reportedStalls.append(event)
    }
    
    func reportRecovery(_ event: RecoveryEvent) {
        reportedRecoveries.append(event)
    }
    
    func reportError(_ event: PlaybackErrorEvent) {
        reportedErrors.append(event)
    }
    
    func reportCPUUsage(_ event: CPUUsageEvent) {
        reportedCPUUsages.append(event)
    }
    
    func reset() {
        reportedStalls = []
        reportedRecoveries = []
        reportedErrors = []
        reportedCPUUsages = []
    }
}
