//
//  MarketingRoute.swift
//  WXYC
//
//  Which tab a `-marketing` recording wants shown.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Which tab the marketing recording wants shown. Written by
/// `MarketingModeController` during a `-marketing` run; `RootTabView` maps it to
/// its private `Page`. Nil in every production launch (mirrors `pendingConcertLink`).
enum MarketingRoute: Sendable {
    case nowPlaying, onTour, liked, station
}
