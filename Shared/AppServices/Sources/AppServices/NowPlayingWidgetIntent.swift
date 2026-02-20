//
//  NowPlayingWidgetIntent.swift
//  AppServices
//
//  A minimal WidgetConfigurationIntent for the NowPlayingWidget. Has no
//  user-configurable parameters; exists solely to enable AppIntentConfiguration
//  and RelevantIntentManager for Smart Stack relevance hints.
//
//  Created by Claude on 02/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if canImport(WidgetKit)
import AppIntents
import WidgetKit

public struct NowPlayingWidgetIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Now Playing"
    public static let description: IntentDescription = "Shows what's currently playing on WXYC."
    public static let isDiscoverable = false

    public init() {}
}
#endif
