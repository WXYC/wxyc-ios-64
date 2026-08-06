//
//  StatusPillStyleMapping.swift
//  WXYC
//
//  Bridges the Concerts package's presenter-level style enums (`FeedTagStyle`,
//  `StatusPillStyle`) to `WXUI.StatusPill.Style`. The mapping is 1:1 by case
//  name — WXUI can't import Concerts (it stays a dependency-free leaf kit), so
//  every ``StatusPill`` call site in the app target converts through here
//  rather than repeating its own switch.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import WXUI

extension FeedTagStyle {
    /// The canon `StatusPill.Style` for this feed-tag style. `FeedTagStyle`
    /// has no `caution` case — rescheduled/unknown fold into `.neutral`, as
    /// they already do in `FeedTagStyle` itself.
    var statusPillStyle: StatusPill.Style {
        switch self {
        case .prominent: .prominent
        case .free: .free
        case .muted: .muted
        case .negative: .negative
        case .neutral: .neutral
        }
    }
}

extension StatusPillStyle {
    /// The canon `StatusPill.Style` for this poster-hero pill style. Case
    /// names match 1:1.
    var wxuiStyle: StatusPill.Style {
        switch self {
        case .prominent: .prominent
        case .free: .free
        case .muted: .muted
        case .negative: .negative
        case .caution: .caution
        case .neutral: .neutral
        }
    }
}
