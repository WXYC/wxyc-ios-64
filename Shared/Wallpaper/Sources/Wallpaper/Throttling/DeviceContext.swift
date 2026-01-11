//
//  DeviceContext.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 1/3/26.
//

#if canImport(UIKit)
import UIKit
#endif
import Foundation
import Observation

/// Protocol for accessing thermal and power state.
///
/// This protocol enables dependency injection for testing the thermal controller.
@MainActor
public protocol DeviceContextProtocol: AnyObject {
    /// The current thermal state from the system.
    var thermalState: ProcessInfo.ThermalState { get }

    /// Whether the device is currently charging or fully charged.
    var isCharging: Bool { get }

    /// Whether low power mode is enabled.
    var isLowPowerMode: Bool { get }

    /// Whether external factors are likely contributing to thermal stress.
    var hasExternalFactors: Bool { get }
}

/// Captures external factors that affect thermal state but aren't shader-related.
///
/// External factors like charging or low power mode can affect thermal readings
/// without being caused by shader workload. This context helps the thermal
/// controller make better decisions about when to persist profile changes.
///
/// Use with `Observations` to react to changes:
/// ```swift
/// for await _ in Observations({ context.thermalState }) {
///     // Handle thermal state change
/// }
/// ```
@Observable
@MainActor
public final class DeviceContext: DeviceContextProtocol {

    /// Shared instance.
    public static let shared = DeviceContext()

    /// The current thermal state from the system.
    public private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Whether the device is currently charging or fully charged.
    public private(set) var isCharging: Bool = false

    /// Whether low power mode is enabled.
    public private(set) var isLowPowerMode: Bool = false

    /// Whether external factors are likely contributing to thermal stress.
    ///
    /// When true, profile changes should not be persisted because the thermal
    /// stress may not be caused by shader workload.
    public var hasExternalFactors: Bool {
        isCharging || isLowPowerMode
    }

    /// Low power mode forced wallpaper FPS (aggressive throttle to save battery).
    public static let lowPowerWallpaperFPS: Float = 30.0

    /// Low power mode forced scale (aggressive throttle to save battery).
    public static let lowPowerScale: Float = 0.5

    @ObservationIgnored
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    private init() {
        // Read initial state
        updateState()

        // Observe system notifications
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateState()
            }
        })

        observers.append(center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateState()
            }
        })

        #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
        observers.append(center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateState()
            }
        })
        #endif
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Must be called once at app startup to enable battery state monitoring.
    ///
    /// Without this, `UIDevice.current.batteryState` always returns `.unknown`.
    public static func enableBatteryMonitoring() {
        #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        // Touch shared to ensure it's initialized
        _ = shared
    }

    private func updateState() {
        thermalState = ProcessInfo.processInfo.thermalState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
        let batteryState = UIDevice.current.batteryState
        isCharging = batteryState == .charging || batteryState == .full
        #else
        isCharging = false
        #endif
    }
}
