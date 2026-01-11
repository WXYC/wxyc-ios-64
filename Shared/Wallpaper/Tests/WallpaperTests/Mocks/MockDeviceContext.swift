//
//  MockDeviceContext.swift
//  WallpaperTests
//
//  Created by Jake Bromberg on 1/3/26.
//

import Foundation
@testable import Wallpaper

/// Mock thermal context for testing with controllable state.
@MainActor
final class MockDeviceContext: DeviceContextProtocol {

    var thermalState: ProcessInfo.ThermalState
    var isCharging: Bool
    var isLowPowerMode: Bool

    var hasExternalFactors: Bool {
        isCharging || isLowPowerMode
    }

    init(
        thermalState: ProcessInfo.ThermalState = .nominal,
        isCharging: Bool = false,
        isLowPowerMode: Bool = false
    ) {
        self.thermalState = thermalState
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
    }
}
