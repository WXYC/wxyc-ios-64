//
//  DebugMetricsProvider.swift
//  DebugPanel
//
//  Protocol for providing debug metrics to the HUD.
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
public final class DebugMetricsProvider {
    // MARK: - Published Metrics

    public private(set) var fps: Int = 0
    public private(set) var cpuUsage: Double = 0
    public private(set) var gpuMemoryMB: Double = 0
    public private(set) var memoryMB: Double = 0
    public private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    // MARK: - Private State

    private var displayLinkTask: Task<Void, Never>?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsAccumulator: CFTimeInterval = 0

    private var metricsTimer: Timer?
    private var thermalTimer: Timer?

    private nonisolated(unsafe) let metalDevice: MTLDevice?

    // MARK: - Initialization

    public init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        setUpDisplayLink()
        setUpTimers()
    }

    func stop() {
        displayLinkTask?.cancel()
        metricsTimer?.invalidate()
        thermalTimer?.invalidate()
    }

    // MARK: - Setup

    private func setUpDisplayLink() {
        displayLinkTask = Task { @MainActor [weak self] in
            for await timestamp in DisplayLinkSequence() {
                self?.handleDisplayLinkTick(timestamp)
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

// MARK: - Display Link Sequence

/// An AsyncSequence that emits timestamps from a CADisplayLink.
private struct DisplayLinkSequence: AsyncSequence {
    typealias Element = CFTimeInterval

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator()
    }

    final class AsyncIterator: AsyncIteratorProtocol {
        private var displayLink: CADisplayLink?
        private var continuation: CheckedContinuation<CFTimeInterval?, Never>?

        init() {
            let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        deinit {
            displayLink?.invalidate()
        }

        func next() async -> CFTimeInterval? {
            guard displayLink != nil else { return nil }

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            continuation?.resume(returning: link.timestamp)
            continuation = nil
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
