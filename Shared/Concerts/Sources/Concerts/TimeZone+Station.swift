//
//  TimeZone+Station.swift
//  Concerts
//
//  The station's broadcast time zone, used to pin `starts_on` date parsing and
//  the Box Office ticket's date/time labels to a fixed zone regardless of the
//  device's locale.
//
//  Declared locally in this package (mirroring the same internal extension in
//  `Shared/Playlist`) so `Concerts` stays self-contained and does not depend on
//  `Playlist` — the dependency runs the other way (Playlist → Concerts). The two
//  module-scoped declarations do not collide.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension TimeZone {
    /// The station's broadcast time zone. WXYC broadcasts from Chapel Hill, NC
    /// (US Eastern). The `?? .gmt` fallback is unreachable for this fixed,
    /// always-known identifier but keeps the declaration force-unwrap-free.
    static let wxycStation = TimeZone(identifier: "America/New_York") ?? .gmt
}
