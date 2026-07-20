//
//  ConcertResolution.swift
//  Concerts
//
//  The outcome of resolving a shared On Tour deep link (#537). A tapped
//  `wxyc.org/shows/<id>` link runs a three-rung ladder: the id is either already
//  in the loaded window (present it with a zoom-from-row transition), fetched
//  individually because it fell outside the window (present it directly), or
//  unresolvable (show the tab with a "couldn't find that show" notice).
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The result of ``OnTourModel/resolveConcert(id:)``.
public enum ConcertResolution: Equatable, Sendable {
    /// The concert was already in the loaded window — the common case for a
    /// friend tapping a link to an upcoming show. Present with a zoom-from-row
    /// transition.
    case window(Concert)

    /// The concert wasn't in the window but a by-id fetch found it (e.g. a show
    /// beyond the loaded page range). Present directly, without a source row.
    case byID(Concert)

    /// Neither the window nor a by-id fetch resolved the id. The tab surfaces a
    /// gentle "couldn't find that show" notice.
    case missed

    /// The resolved concert, or `nil` for ``missed``.
    public var concert: Concert? {
        switch self {
        case .window(let concert), .byID(let concert):
            concert
        case .missed:
            nil
        }
    }

    /// The stable label for the `ConcertDeepLinkOpened.resolution` analytics
    /// property. Carries only the rung that resolved the link — never the
    /// concert or artist identity (the On Tour privacy invariant).
    public var analyticsLabel: String {
        switch self {
        case .window: "window"
        case .byID: "byID"
        case .missed: "missed"
        }
    }
}
