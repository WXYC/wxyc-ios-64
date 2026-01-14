//
//  CPUMonitor.swift
//  Playback
//
//  Monitors CPU usage during audio streaming for analytics.
//
//  Created by Jake Bromberg on 12/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Darwin

/// Monitors CPU usage of the current process
@MainActor
public final class CPUMonitor {
    private var monitoringTask: Task<Void, Never>?
    private let interval: TimeInterval
    private let onUpdate: @MainActor (Double) -> Void
    
    /// Initializes the CPU monitor
    /// - Parameters:
    ///   - interval: Sampling interval in seconds (default 5.0)
    ///   - onUpdate: Closure called with the CPU usage percentage (0.0 - 100.0+)
    public init(interval: TimeInterval = 5.0, onUpdate: @escaping @MainActor (Double) -> Void) {
        self.interval = interval
        self.onUpdate = onUpdate
    }
                
    /// Starts monitoring CPU usage
    public func start() {
        stop()
        
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                
                self.checkCPU()
                
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }
    
    /// Stops monitoring
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    private func checkCPU() {
        let usage = self.getCPUUsage()
        self.onUpdate(usage)
    }
    
    // Derived from: https://stackoverflow.com/questions/8223348/ios-get-cpu-usage-from-application
    private func getCPUUsage() -> Double {
        var kernIsOk: kern_return_t
        var taskInfo = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        kernIsOk = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kernIsOk != KERN_SUCCESS {
            return -1.0
        }
        
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        kernIsOk = task_threads(mach_task_self_, &threadList, &threadCount)
        
        if kernIsOk != KERN_SUCCESS {
            return -1.0
        }
        
        guard let threadList else {
            return 0.0
        }
        
        var totalUsageOfCPU: Double = 0.0
        
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            
            let threadReturn = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(threadInfoCount)) {
                    thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }
            
            guard threadReturn == KERN_SUCCESS else { continue }
            
            let flags = threadInfo.flags
            guard flags & TH_FLAGS_IDLE == 0 else { continue }
        
            totalUsageOfCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
        }
        
        let itemSize = MemoryLayout<thread_t>.stride
        let totalSize = Int(threadCount) * itemSize
        let address = unsafeBitCast(threadList, to: vm_address_t.self)
        vm_deallocate(mach_task_self_, address, vm_size_t(totalSize))

        return totalUsageOfCPU
    }
}
