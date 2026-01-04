//
//  ReviewRequestServiceEnvironment.swift
//  AppServices
//
//  SwiftUI Environment support for ReviewRequestService.
//

import SwiftUI

private struct ReviewRequestServiceKey: EnvironmentKey {
    static let defaultValue: ReviewRequestService? = nil
}

public extension EnvironmentValues {
    var reviewRequestService: ReviewRequestService? {
        get { self[ReviewRequestServiceKey.self] }
        set { self[ReviewRequestServiceKey.self] = newValue }
    }
}
