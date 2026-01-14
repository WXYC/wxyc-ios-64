//
//  CPUSessionAggregator.swift
//  Playback
//
//  Aggregates CPU samples into session-level events.
//
//  Created by Jake Bromberg on 01/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PlaybackCore

/// Aggregates CPU samples into session-level events.
///
/// Collects 5-second samples during playback and reports aggregate
/// statistics when sessions end (stop, background/foreground transitions).
@MainActor
public final class CPUSessionAggregator {

    /// Default sampling interval in seconds.
    public static let samplingInterval: TimeInterval = 5.0

    private let analytics: PlaybackAnalytics
    private let playerTypeProvider: () -> PlayerControllerType

    private var cpuMonitor: CPUMonitor?
    private var currentContext: PlaybackContext = .foreground
    private var sessionStart: Date?
    private var isActive = false

    // Running aggregates
    private var cpuSum: Double = 0
    private var cpuMax: Double = 0
    private var sampleCount: Int = 0

    /// Creates an aggregator with the specified analytics and player type provider.
    ///
    /// - Parameters:
    ///   - analytics: The analytics instance to report session events to.
    ///   - playerTypeProvider: A closure that returns the current player type.
    public init(
        analytics: PlaybackAnalytics,
        playerTypeProvider: @escaping () -> PlayerControllerType
    ) {
        self.analytics = analytics
        self.playerTypeProvider = playerTypeProvider
    }

    // MARK: - Session Control

    /// Starts a new CPU monitoring session.
    ///
    /// - Parameter context: Whether this is foreground or background playback.
    public func startSession(context: PlaybackContext) {
        guard !isActive else { return }

        resetAggregates()
        currentContext = context
        sessionStart = Date()
        isActive = true

        cpuMonitor = CPUMonitor(interval: Self.samplingInterval) { [weak self] usage in
            self?.recordSample(usage)
        }
        cpuMonitor?.start()
    }

    /// Ends the current CPU monitoring session and reports the aggregate event.
    ///
    /// - Parameter reason: Why the session ended.
    public func endSession(reason: CPUSessionEndReason) {
        guard isActive else { return }

        cpuMonitor?.stop()
        cpuMonitor = nil
        isActive = false

        flush(reason: reason)
    }

    /// Transitions the playback context (foreground/background).
    ///
    /// This ends the current session with an appropriate reason and starts
    /// a new session in the new context.
    ///
    /// - Parameter newContext: The new playback context.
    public func transitionContext(to newContext: PlaybackContext) {
        guard newContext != currentContext, isActive else { return }

        // End current session with appropriate reason
        let endReason: CPUSessionEndReason = (newContext == .background) ? .backgrounded : .foregrounded

        // Stop monitoring temporarily
        cpuMonitor?.stop()
        cpuMonitor = nil

        // Flush the current session
        flush(reason: endReason)

        // Start new session in new context
        resetAggregates()
        currentContext = newContext
        sessionStart = Date()

        cpuMonitor = CPUMonitor(interval: Self.samplingInterval) { [weak self] usage in
            self?.recordSample(usage)
        }
        cpuMonitor?.start()
    }

    /// Returns whether a session is currently active.
    public var isSessionActive: Bool {
        isActive
    }

    // MARK: - Testing Support

    /// Manually injects a CPU sample for testing purposes.
    ///
    /// This allows tests to verify aggregation logic without waiting for
    /// real CPU sampling to occur.
    ///
    /// - Parameter usage: The CPU usage percentage to record.
    internal func _testInjectSample(_ usage: Double) {
        recordSample(usage)
    }

    /// Starts a session without creating a real CPUMonitor.
    ///
    /// Use this for unit tests that want to manually inject samples.
    ///
    /// - Parameter context: Whether this is foreground or background playback.
    internal func _testStartSessionWithoutMonitor(context: PlaybackContext) {
        guard !isActive else { return }

        resetAggregates()
        currentContext = context
        sessionStart = Date()
        isActive = true
    }

    // MARK: - Private

    private func recordSample(_ usage: Double) {
        guard usage >= 0 else { return } // Invalid reading

        cpuSum += usage
        cpuMax = max(cpuMax, usage)
        sampleCount += 1
    }

    private func flush(reason: CPUSessionEndReason) {
        guard sampleCount > 0, let start = sessionStart else { return }

        let duration = Date().timeIntervalSince(start)
        let average = cpuSum / Double(sampleCount)

        let event = CPUSessionEvent(
            playerType: playerTypeProvider(),
            context: currentContext,
            endReason: reason,
            averageCPU: average,
            maxCPU: cpuMax,
            sampleCount: sampleCount,
            durationSeconds: duration
        )

        analytics.capture(event)
    }

    private func resetAggregates() {
        cpuSum = 0
        cpuMax = 0
        sampleCount = 0
        sessionStart = nil
    }
}
