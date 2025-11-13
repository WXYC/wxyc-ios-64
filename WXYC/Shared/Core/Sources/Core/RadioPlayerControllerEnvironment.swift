//
//  RadioPlayerControllerEnvironment.swift
//  Core
//
//  SwiftUI Environment support for RadioPlayerController
//

import SwiftUI

// MARK: - Environment Key

private struct RadioPlayerControllerKey: EnvironmentKey {
    static let defaultValue: RadioPlayerController? = nil
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    var radioPlayerController: RadioPlayerController? {
        get { self[RadioPlayerControllerKey.self] }
        set { self[RadioPlayerControllerKey.self] = newValue }
    }
}

