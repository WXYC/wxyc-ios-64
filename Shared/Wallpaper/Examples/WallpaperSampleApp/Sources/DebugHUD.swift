//
//  DebugHUD.swift
//  WallpaperSampleApp
//
//  Copied from DebugPanel for shader performance testing.
//

import SwiftUI
import Metal
import QuartzCore

/// A debug HUD overlay displaying real-time performance metrics.
struct DebugHUD: View {
    @State private var metrics = DebugMetricsProvider()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MetricRow(label: "FPS", value: "\(metrics.fps)")
            MetricRow(label: "CPU", value: metrics.cpuUsage.formatted(.number.precision(.fractionLength(1))) + "%")
            MetricRow(label: "GPU", value: metrics.gpuMemoryMB.formatted(.number.precision(.fractionLength(1))) + " MB")
            MetricRow(label: "MEM", value: metrics.memoryMB.formatted(.number.precision(.fractionLength(1))) + " MB")
            MetricRow(label: "TMP", value: metrics.thermalState.description)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.6))
        .clipShape(.rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 50)
        .padding(.trailing, 8)
        .allowsHitTesting(false)
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .frame(width: 32, alignment: .leading)
            Text(value)
        }
    }
}

// MARK: - Metrics Provider

@MainActor
@Observable
final class DebugMetricsProvider {
    private(set) var fps: Int = 0
    private(set) var cpuUsage: Double = 0
    private(set) var gpuMemoryMB: Double = 0
    private(set) var memoryMB: Double = 0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    private var displayLinkTask: Task<Void, Never>?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsAccumulator: CFTimeInterval = 0

    private var metricsTimer: Timer?
    private var thermalTimer: Timer?

    private let metalDevice: (any MTLDevice)?

    init() {
        self.metalDevice = MTLCreateSystemDefaultDevice()
        setUpDisplayLink()
        setUpTimers()
    }

    private func setUpDisplayLink() {
        displayLinkTask = Task { @MainActor [weak self] in
            for await timestamp in DisplayLinkSequence() {
                self?.handleDisplayLinkTick(timestamp)
            }
        }
    }

    private func setUpTimers() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }

        thermalTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateThermalState()
            }
        }

        updateMetrics()
        updateThermalState()
    }

    private func handleDisplayLinkTick(_ timestamp: CFTimeInterval) {
        if lastTimestamp == 0 {
            lastTimestamp = timestamp
            return
        }

        let elapsed = timestamp - lastTimestamp
        lastTimestamp = timestamp
        frameCount += 1
        fpsAccumulator += elapsed

        if fpsAccumulator >= 0.5 {
            fps = Int(Double(frameCount) / fpsAccumulator)
            frameCount = 0
            fpsAccumulator = 0
        }
    }

    private func updateMetrics() {
        cpuUsage = measureCPUUsage()
        memoryMB = measureMemoryUsage()
        gpuMemoryMB = measureGPUMemory()
    }

    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
    }

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

    private func measureGPUMemory() -> Double {
        guard let device = metalDevice else { return 0 }
        return Double(device.currentAllocatedSize) / 1_048_576
    }
}

// MARK: - Display Link Sequence

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
    var description: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
