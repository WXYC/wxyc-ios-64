import Foundation
import PostHog

public protocol PlaybackMetricsReporter {
    func reportStall(_ event: StallEvent)
    func reportRecovery(_ event: RecoveryEvent)
    func reportError(_ event: PlaybackErrorEvent)
    func reportCPUUsage(_ event: CPUUsageEvent)
}

extension PostHogSDK: PlaybackMetricsReporter {
    public func reportStall(_ event: StallEvent) {
        capture("playback_stalled", properties: event.properties)
    }
    
    public func reportRecovery(_ event: RecoveryEvent) {
        capture("playback_recovery", properties: event.properties)
    }
    
    public func reportError(_ event: PlaybackErrorEvent) {
        capture("playback_error", properties: event.properties)
    }
    
    public func reportCPUUsage(_ event: CPUUsageEvent) {
        capture("cpu_usage", properties: event.properties)
    }
}
