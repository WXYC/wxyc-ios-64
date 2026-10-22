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
/// - ``dj(_:show:)`` — an `on_air` object with a `dj_name`: a named DJ is live, optionally
///   with the show they signed on as.
/// - ``automation`` — an explicit JSON `null`: the station is confirmed on
///   automation between shows ("Auto DJ").
/// - ``unknown`` — the field is absent entirely: an older backend, the v1
///   endpoint, or a non-default query branch that does not report on-air
///   status. The banner hides rather than assert a false "Auto DJ".
public enum OnAir: Codable, Sendable, Equatable {
    /// A named DJ is on the air, with the open show's identity when the backend reports one.
    case dj(String, show: OnAirShow? = nil)
    /// The station is confirmed on automation.
    case automation
    /// The on-air status is unreported; treat as "don't know."
    case unknown
}

/// The open show behind a live ``OnAir/dj(_:show:)``: its id, its title, the specialty
/// program the DJ signed on as, and its current who's-on entry. The app shows a program only when
/// `specialty` is set; it never infers one from the time slot.
public struct OnAirShow: Codable, Sendable, Hashable {
    public let id: UInt64?
    public let title: String?
    public let specialty: SpecialtyShowRef?
    /// The newest spotlight row of the open show, as the server computes it (`on_air.spotlight`).
    public let spotlight: SpotlightEntry?

    public init(id: UInt64?, title: String?, specialty: SpecialtyShowRef?, spotlight: SpotlightEntry? = nil) {
        self.id = id
        self.title = title
        self.specialty = specialty
        self.spotlight = spotlight
    }
}

public extension OnAir {
    /// The on-air banner headline for this state, or `nil` when the banner
    /// should be hidden.
    ///
    /// `nil` for ``unknown`` — with no reported status we hide the banner
    /// rather than falsely claim automation.
    var bannerTitle: String? {
        switch self {
        case .dj(let name, _): name
        case .automation: "Auto DJ"
        case .unknown: nil
        }
    }
}
