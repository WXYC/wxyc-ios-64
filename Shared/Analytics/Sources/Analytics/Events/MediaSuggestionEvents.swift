//
//  MediaSuggestionEvents.swift
//  Analytics
//
//  Structured analytics for the #828 media-suggestion eligibility
//  declaration (INMediaUserContext + INUpcomingMediaManager). The follow-on
//  device observation (docs/plans/media-suggestion-headphones.md) reads
//  PlaybackStartedEvent.reason against a launch-time baseline to tell "a
//  tile fired" from "no tile at all" — but that alone can't distinguish
//  "iOS declined to suggest" from "MediaSuggestionService.register() never
//  ran," e.g. because the `#if os(iOS) && !targetEnvironment(macCatalyst)`
//  gate excluded the build. MediaSuggestionRegistered is that missing
//  baseline: it fires once per launch, right after registration, so the
//  observation is falsifiable rather than a guess.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired when `MediaSuggestionService.register()` (AppServices)
/// publishes an `INMediaUserContext` and seeds `INUpcomingMediaManager` with
/// the WXYC play intent. No properties — its presence or absence per launch
/// is the whole signal.
@AnalyticsEvent
public struct MediaSuggestionRegistered {
    public init() {}
}
