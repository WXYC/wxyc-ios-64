//
//  OnAir.swift
//  Playlist
//
//  Tri-state on-air signal carried by a Playlist: who (if anyone) the backend
//  reports is currently on the air.
//
//  Created by Jake Bromberg on 07/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Whether a DJ is on the air, as reported by the backend's `on_air` field.
///
/// This is deliberately three-state so the banner can tell "nobody is on"
/// (automation) apart from "we don't know who's on." The v2 flowsheet API
/// distinguishes the states by JSON shape (see ``FlowsheetResponse``):
///
/// - ``dj(_:)`` — an `on_air` object with a `dj_name`: a named DJ is live.
/// - ``automation`` — an explicit JSON `null`: the station is confirmed on
///   automation between shows ("Auto DJ").
/// - ``unknown`` — the field is absent entirely: an older backend, the v1
///   endpoint, or a non-default query branch that does not report on-air
///   status. The banner hides rather than assert a false "Auto DJ".
public enum OnAir: Codable, Sendable, Equatable {
    /// A named DJ is on the air.
    case dj(String)
    /// The station is confirmed on automation.
    case automation
    /// The on-air status is unreported; treat as "don't know."
    case unknown
}

public extension OnAir {
    /// The on-air banner headline for this state, or `nil` when the banner
    /// should be hidden.
    ///
    /// `nil` for ``unknown`` — with no reported status we hide the banner
    /// rather than falsely claim automation.
    var bannerTitle: String? {
        switch self {
        case .dj(let name): name
        case .automation: "Auto DJ"
        case .unknown: nil
        }
    }
}
