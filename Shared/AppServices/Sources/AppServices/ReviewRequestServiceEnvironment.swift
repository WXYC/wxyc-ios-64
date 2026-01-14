//
//  ReviewRequestServiceEnvironment.swift
//  AppServices
//
//  SwiftUI Environment support for ReviewRequestService.
//
//  Created by Jake Bromberg on 01/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
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
