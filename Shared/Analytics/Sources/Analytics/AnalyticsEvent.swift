//
//  AnalyticsEvent.swift
//  Analytics
//
//  Defines the AnalyticsEvent protocol for type-safe, structured analytics tracking.
//
//  Created by Antigravity on 01/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A structured analytics event that can be tracked.
public protocol AnalyticsEvent: Sendable {
    /// The name of the event to track.
    var name: String { get }
    
    /// The properties associated with the event.
    var properties: [String: Any]? { get }
}
