//
//  DebugMetricsProvider.swift
//  DebugPanel
//
//  Real-time performance metrics for the debug HUD, and the display-link source
//  that feeds them. Both only run while the HUD is on screen — see
//  DebugMetricsProvider.start() and DisplayLinkSource.
//
//  Created by Jake Bromberg on 12/23/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Metal
import QuartzCore

/// Provides real-time performance metrics for the debug HUD.
@MainActor
@Observable
final class DebugMetricsProvider {
    // MARK: - Published Metrics

    private(set) var fps: Int = 0
    private(set) var cpuUsage: Double = 0
    private(set) var gpuMemoryMB: Double = 0
    private(set) var memoryMB: Double = 0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Whether the sampling sources are attached.
    ///
    /// Sampling costs a display-rate run-loop wakeup plus two timers, so it runs
    /// only while the HUD is actually on screen — see ``start()``.
    private(set) var isRunning = false

    // MARK: - Private State

    private var displayLinkTask: Task<Void, Never>?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsAccumulator: CFTimeInterval = 0

    private var metricsTimer: Timer?
    private var thermalTimer: Timer?

    private nonisolated(unsafe) let metalDevice: MTLDevice?

    // MARK: - Initialization

    /// Construction is deliberately inert — no display link, no timers.
    ///
    /// ``DebugHUD`` holds this in `@State`, and a `@State` initializer expression
    /// is re-evaluated every time the view struct is created even though SwiftUI
    /// keeps only the first instance. An `init` that attached a display link
    /// therefore stranded one per discarded copy, each still waking the app at
    /// display rate. Sampling begins at ``start()`` instead.
    init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
    }

    // MARK: - Lifecycle

    /// Attaches the display link and the metric timers. Idempotent.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        setUpDisplayLink()
        setUpTimers()
    }

    /// Detaches everything ``start()`` attached. Idempotent.
    ///
    /// Cancelling `displayLinkTask` ends its `for await`, which terminates the
    /// stream, which is what invalidates the underlying `CADisplayLink` — see
    /// ``DisplayLinkSource``.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        displayLinkTask?.cancel()
        displayLinkTask = nil

        metricsTimer?.invalidate()
        metricsTimer = nil
        thermalTimer?.invalidate()
        thermalTimer = nil

        // Reset the FPS accumulator so the next `start()` measures a fresh
        // window rather than folding in the gap while the HUD was hidden.
        lastTimestamp = 0
        frameCount = 0
        fpsAccumulator = 0
    }

    // MARK: - Setup

    private func setUpDisplayLink() {
        displayLinkTask = Task { @MainActor [weak self] in
            for await timestamp in DisplayLinkSource.timestamps() {
                // Breaking (rather than skipping) on a released provider ends the
                // stream, which releases the link. A `self?.` call here would
                // leave the loop — and the link — running forever.
                guard let self else { break }
                self.handleDisplayLinkTick(timestamp)
            }
        }
    }

    private func setUpTimers() {
        // Update CPU/Memory/GPU every second
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }

        // Update thermal state every 5 seconds
        thermalTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateThermalState()
            }
        }

        // Initial update
        updateMetrics()
        updateThermalState()
    }

    // MARK: - FPS Calculation

    private func handleDisplayLinkTick(_ timestamp: CFTimeInterval) {
        if lastTimestamp == 0 {
            lastTimestamp = timestamp
            return
        }

        let elapsed = timestamp - lastTimestamp
        lastTimestamp = timestamp
        frameCount += 1
        fpsAccumulator += elapsed

        // Update FPS every 0.5 seconds for stability
        if fpsAccumulator >= 0.5 {
            fps = Int(Double(frameCount) / fpsAccumulator)
            frameCount = 0
            fpsAccumulator = 0
        }
    }

    // MARK: - Metrics Updates

    private func updateMetrics() {
        cpuUsage = measureCPUUsage()
        memoryMB = measureMemoryUsage()
        gpuMemoryMB = measureGPUMemory()
    }

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
    }

    // MARK: - CPU Usage

    private func measureCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else {
            return 0
        }

        defer {
            let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)
        }

        var totalUsage: Double = 0

        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)

            let infoResult = withUnsafeMutablePointer(to: &info) { infoPtr in
                infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &count)
                }
            }

            if infoResult == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }

        return totalUsage
    }

    // MARK: - Memory Usage

    private func measureMemoryUsage() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        return Double(info.phys_footprint) / 1_048_576
    }

    // MARK: - GPU Memory

    private func measureGPUMemory() -> Double {
        guard let device = metalDevice else { return 0 }
        return Double(device.currentAllocatedSize) / 1_048_576
    }
}

// MARK: - Display Link Source

/// Vends display-refresh timestamps as an `AsyncStream`, and owns the teardown
/// the run loop won't do for you.
///
/// `CADisplayLink` retains its target, and adding it to a run loop hands the run
/// loop a strong reference to the link. Nothing here may therefore *target* an
/// object whose lifetime is meant to gate the link: the earlier version made the
/// async iterator its own target, so the link kept the iterator alive, `deinit`
/// never ran, and `invalidate()` — which only `deinit` called — never fired. The
/// app kept a display-rate wakeup for every iterator it had ever created.
///
/// Instead the target is a standalone ``Proxy`` holding only the stream's
/// continuation, and the link is released from `onTermination`, which fires when
/// the consuming task is cancelled or its `for await` loop breaks.
@MainActor
enum DisplayLinkSource {
    private static var links: [Int: CADisplayLink] = [:]
    private static var nextToken = 0

    /// Links currently attached to the run loop and not yet released.
    ///
    /// A diagnostic seam in the spirit of `AudioPlayerController.debugStateSnapshot`:
    /// teardown is the part that regresses, and it is otherwise unobservable from
    /// a test.
    static var activeLinkCount: Int { links.count }

    /// Display-refresh timestamps, delivered until the consuming task ends.
    ///
    /// Buffers only the newest timestamp — a consumer that falls behind wants the
    /// current frame, not a backlog of stale ones.
    static func timestamps() -> AsyncStream<CFTimeInterval> {
        let (stream, continuation) = AsyncStream<CFTimeInterval>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let token = nextToken
        nextToken += 1

        let proxy = Proxy(continuation: continuation)
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        links[token] = link

        // Only the token — an `Int` — crosses into the `@Sendable` termination
        // handler. The link itself stays main-actor-confined in `links`.
        continuation.onTermination = { _ in
            Task { @MainActor in DisplayLinkSource.release(token) }
        }

        return stream
    }

    private static func release(_ token: Int) {
        links.removeValue(forKey: token)?.invalidate()
    }

    /// The `CADisplayLink` target. Holds the continuation rather than the
    /// consumer, so the link can never pin its own owner alive.
    private final class Proxy: NSObject {
        private let continuation: AsyncStream<CFTimeInterval>.Continuation

        init(continuation: AsyncStream<CFTimeInterval>.Continuation) {
            self.continuation = continuation
        }

        @objc func tick(_ link: CADisplayLink) {
            continuation.yield(link.timestamp)
        }
    }
}

// MARK: - Thermal State Description

extension ProcessInfo.ThermalState {
    /// Human-readable description of the thermal state.
    public var description: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
