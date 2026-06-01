//
//  UserAgentHeader.swift
//  MusicShareKit
//
//  Builds the `User-Agent: WXYC-iOS/<version>` value advertised to ROM and BS.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The `User-Agent` header value sent on every WXYC iOS network request.
///
/// Format: `WXYC-iOS/<CFBundleShortVersionString>`. Used by ROM#155's UA gate
/// to identify registered WXYC clients and apply the strict-fingerprint check
/// at-or-above iOS 3.2. An unparseable version falls through to the lenient
/// path (the gate requires dotted-numeric versions).
///
/// Cached at first read; `CFBundleShortVersionString` doesn't change between
/// launches. Single immutable implementation, so the enum-namespace pattern
/// is appropriate here (unlike `TokenStorage` / `DeviceFingerprintStorage`
/// which need a test seam — see D6 in the iOS#351 plan).
internal enum UserAgentHeader {

    /// Header value, e.g. `"WXYC-iOS/3.2"`. Falls back to
    /// `"WXYC-iOS/unknown"` if the Info.plist read fails.
    static let value: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            as? String ?? "unknown"
        return "WXYC-iOS/\(version)"
    }()
}
