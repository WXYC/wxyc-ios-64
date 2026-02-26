//
//  PlaylistEvents.swift
//  Analytics
//
//  Structured analytics events for playlist fetching.
//
//  Created by Jake Bromberg on 02/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired when a playlist fetch succeeds.
@AnalyticsEvent
public struct PlaylistFetchSuccess {
    public let duration: String
    public let apiVersion: String

    public init(duration: TimeInterval, apiVersion: String) {
        self.duration = "\(duration)"
        self.apiVersion = apiVersion
    }
}
