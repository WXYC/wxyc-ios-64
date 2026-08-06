//
//  MockAudioSession.swift
//  Playback
//
//  Mock implementation of AudioSessionProtocol for testing
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import os
@testable import Playback

#if os(iOS) || os(tvOS) || os(watchOS)

/// Mock audio session for testing (iOS/tvOS/watchOS).
///
/// Every property is lock-protected because `AudioPlayerController` deactivates
/// the session off the main actor (see `scheduleAudioSessionDeactivation()`), so
/// a test's `waitUntil` reads these counters on the main actor while the
/// deactivation writes them from a background executor. The real `AVAudioSession`
/// is thread-safe; this stands in for it, so it has to be too.
public final class MockAudioSession: AudioSessionProtocol, @unchecked Sendable {

    /// Everything the mock records or is configured with, so one lock covers the
    /// whole of it.
    private struct State: @unchecked Sendable {
        var setCategoryCallCount = 0
        var setActiveCallCount = 0

        var lastCategory: AVAudioSession.Category?
        var lastMode: AVAudioSession.Mode?
        var lastCategoryOptions: AVAudioSession.CategoryOptions?
        var lastPolicy: AVAudioSession.RouteSharingPolicy?
        var lastActiveState: Bool?
        var lastActiveOptions: AVAudioSession.SetActiveOptions?

        var shouldThrowOnSetCategory = false
        var shouldThrowOnSetActive = false
        var setActiveError: (any Error)?
        var failSetActiveCount = 0
        var outputLatency: TimeInterval = 0
        var deactivationHoldArmed = false
        var shouldThrowOnDeactivate = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - State Tracking

    public var setCategoryCallCount: Int {
        get { state.withLock { $0.setCategoryCallCount } }
        set { state.withLock { $0.setCategoryCallCount = newValue } }
    }

    public var setActiveCallCount: Int {
        get { state.withLock { $0.setActiveCallCount } }
        set { state.withLock { $0.setActiveCallCount = newValue } }
    }

    public var lastCategory: AVAudioSession.Category? {
        get { state.withLock { $0.lastCategory } }
        set { state.withLock { $0.lastCategory = newValue } }
    }

    public var lastMode: AVAudioSession.Mode? {
        get { state.withLock { $0.lastMode } }
        set { state.withLock { $0.lastMode = newValue } }
    }

    public var lastCategoryOptions: AVAudioSession.CategoryOptions? {
        get { state.withLock { $0.lastCategoryOptions } }
        set { state.withLock { $0.lastCategoryOptions = newValue } }
    }

    public var lastPolicy: AVAudioSession.RouteSharingPolicy? {
        get { state.withLock { $0.lastPolicy } }
        set { state.withLock { $0.lastPolicy = newValue } }
    }

    public var lastActiveState: Bool? {
        get { state.withLock { $0.lastActiveState } }
        set { state.withLock { $0.lastActiveState = newValue } }
    }

    public var lastActiveOptions: AVAudioSession.SetActiveOptions? {
        get { state.withLock { $0.lastActiveOptions } }
        set { state.withLock { $0.lastActiveOptions = newValue } }
    }

    public var shouldThrowOnSetCategory: Bool {
        get { state.withLock { $0.shouldThrowOnSetCategory } }
        set { state.withLock { $0.shouldThrowOnSetCategory = newValue } }
    }

    public var shouldThrowOnSetActive: Bool {
        get { state.withLock { $0.shouldThrowOnSetActive } }
        set { state.withLock { $0.shouldThrowOnSetActive = newValue } }
    }

    /// When non-nil, `setActive(true, …)` throws this error instead of the
    /// generic `MockAudioSessionError.setActiveFailed`. Lets tests reproduce a
    /// specific `com.apple.coreaudio.avfaudio` `CannotInterruptOthers` failure.
    public var setActiveError: (any Error)? {
        get { state.withLock { $0.setActiveError } }
        set { state.withLock { $0.setActiveError = newValue } }
    }

    /// Number of leading `setActive(true, …)` calls that should fail before the
    /// session begins activating successfully. Decrements on each activation
    /// attempt. Used to model a transient "can't interrupt other audio" state
    /// that clears after a bounded retry. `shouldThrowOnSetActive` still forces
    /// every activation to fail when set.
    public var failSetActiveCount: Int {
        get { state.withLock { $0.failSetActiveCount } }
        set { state.withLock { $0.failSetActiveCount = newValue } }
    }

    /// Configurable output latency for testing AirPlay delay scenarios
    public var outputLatency: TimeInterval {
        get { state.withLock { $0.outputLatency } }
        set { state.withLock { $0.outputLatency = newValue } }
    }

    /// Arms the deactivation gate: every subsequent `setActive(false, …)`
    /// records the call and then blocks until `releaseDeactivations()` opens
    /// the gate, modelling the hundreds-of-milliseconds XPC round-trip the
    /// real session makes — but driven by the test's signal rather than the
    /// wall clock, so a stalled scheduler can neither let the hold lapse
    /// before the test's next step (a vacuous pass) nor stretch a sleep into
    /// a spurious failure. The block happens outside the state lock, so the
    /// recorded call is observable while it is still "in flight".
    ///
    /// `deactivationHoldCap` bounds the block: a regression that routes a
    /// *blocking* caller through the gate — the main actor waiting out the
    /// handback is the defect #773 fixed — fails its test's elapsed bound
    /// instead of deadlocking the suite.
    public func holdDeactivations() {
        state.withLock { $0.deactivationHoldArmed = true }
    }

    /// Opens the gate: a currently blocked deactivation returns within ~1ms,
    /// and later ones pass straight through. Idempotent. `reset()` also opens
    /// it, so a held mock can't strand a blocked thread past its test.
    public func releaseDeactivations() {
        state.withLock { $0.deactivationHoldArmed = false }
    }

    /// Upper bound on how long an armed gate holds a deactivation open.
    /// Generous enough that no healthy path ever reaches it; small enough
    /// that a regression fails inside the suite's patience.
    public static let deactivationHoldCap: Duration = .seconds(5)

    /// When true, `setActive(false, …)` throws. Deactivation otherwise always
    /// succeeds — `shouldThrowOnSetActive` only models activation failures.
    public var shouldThrowOnDeactivate: Bool {
        get { state.withLock { $0.shouldThrowOnDeactivate } }
        set { state.withLock { $0.shouldThrowOnDeactivate = newValue } }
    }

    public init() {}

    // MARK: - AudioSessionProtocol

    public func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws {
        try state.withLock { state in
            state.setCategoryCallCount += 1
            state.lastCategory = category
            state.lastMode = mode
            state.lastCategoryOptions = options

            if state.shouldThrowOnSetCategory {
                throw MockAudioSessionError.setCategoryFailed
            }
        }
    }

    public func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, policy: AVAudioSession.RouteSharingPolicy, options: AVAudioSession.CategoryOptions) throws {
        try state.withLock { state in
            state.setCategoryCallCount += 1
            state.lastCategory = category
            state.lastMode = mode
            state.lastPolicy = policy
            state.lastCategoryOptions = options

            if state.shouldThrowOnSetCategory {
                throw MockAudioSessionError.setCategoryFailed
            }
        }
    }

    public func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        let shouldBlock: Bool = try state.withLock { state in
            state.setActiveCallCount += 1
            state.lastActiveState = active
            state.lastActiveOptions = options

            // Only activation (true) is subject to the transient-failure model;
            // deactivation fails only when a test asks it to.
            if active {
                if state.shouldThrowOnSetActive {
                    throw state.setActiveError ?? MockAudioSessionError.setActiveFailed
                }
                if state.failSetActiveCount > 0 {
                    state.failSetActiveCount -= 1
                    throw state.setActiveError ?? MockAudioSessionError.setActiveFailed
                }
                return false
            }

            if state.shouldThrowOnDeactivate {
                throw MockAudioSessionError.setActiveFailed
            }
            return state.deactivationHoldArmed
        }

        // Blocked outside the state lock so a test polling the recorded call
        // isn't blocked by the very hold it is waiting on. A 1ms poll rather
        // than a condition variable: the blocked thread is the controller's
        // detached handback task, so the wait is honest about being a blocked
        // thread while staying release-driven instead of duration-driven.
        if shouldBlock {
            let clock = ContinuousClock()
            let deadline = clock.now + Self.deactivationHoldCap
            while state.withLock({ $0.deactivationHoldArmed }), clock.now < deadline {
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }

    public var currentRoute: AVAudioSessionRouteDescription {
        AVAudioSession.sharedInstance().currentRoute
    }

    // MARK: - Test Helpers

    public func reset() {
        state.withLock { $0 = State() }
    }
}

#else

/// Mock audio session for testing (macOS)
public final class MockAudioSession: AudioSessionProtocol, @unchecked Sendable {

    private struct State: Sendable {
        var setActiveCallCount = 0
        var lastActiveState: Bool?
        var shouldThrowOnSetActive = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - State Tracking

    public var setActiveCallCount: Int {
        get { state.withLock { $0.setActiveCallCount } }
        set { state.withLock { $0.setActiveCallCount = newValue } }
    }

    public var lastActiveState: Bool? {
        get { state.withLock { $0.lastActiveState } }
        set { state.withLock { $0.lastActiveState = newValue } }
    }

    public var shouldThrowOnSetActive: Bool {
        get { state.withLock { $0.shouldThrowOnSetActive } }
        set { state.withLock { $0.shouldThrowOnSetActive = newValue } }
    }

    public init() {}

    // MARK: - AudioSessionProtocol

    public func setActive(_ active: Bool) throws {
        try state.withLock { state in
            state.setActiveCallCount += 1
            state.lastActiveState = active

            if state.shouldThrowOnSetActive {
                throw MockAudioSessionError.setActiveFailed
            }
        }
    }

    // MARK: - Test Helpers

    public func reset() {
        state.withLock { $0 = State() }
    }
}

#endif

public enum MockAudioSessionError: Error {
    case setCategoryFailed
    case setActiveFailed
}
