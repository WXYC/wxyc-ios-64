//
//  MarketingRoute.swift
//  WXYC
//
//  Which tab a `-marketing` recording wants shown.
//
//  Created by Jake Bromberg on 07/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

/// Which section the marketing recording wants shown. Written by
/// `MarketingModeController` during a `-marketing` run; `RootTabView` maps it to
/// an `AppSection`. Nil in every production launch (mirrors `pendingConcertLink`).
enum MarketingRoute: Sendable {
    case nowPlaying, onTour, liked, station
}

extension MarketingRoute {
    /// The app section this route drives. Total (never fails); the
    /// `RootTabView.onChange` call site treats a `nil` route as a no-op, so this
    /// stays a pure, directly-testable mapping. Lives on `MarketingRoute` — the
    /// iOS-only marketing type — rather than on `AppSection`, so the shared
    /// section enum never has to import the marketing surface.
    var section: AppSection {
        switch self {
        case .nowPlaying: .playlist
        case .onTour: .onTour
        case .liked: .liked
        case .station: .station
        }
    }
}
