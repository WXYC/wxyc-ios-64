//
//  DJAppLink.swift
//  Playlist
//
//  Builds the `wxycdj://album/<id>` deep link that opens a playcut's catalog
//  album in the WXYC DJ app (wxyc-dj-ios), where the DJ's Add to Bin finishes
//  the job. Backs the playcut detail's "Open in WXYC DJ" button (#1151).
//
//  Created by Jake Bromberg on 10/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

public enum DJAppLink {
    /// The URL scheme the DJ app registers. Also listed under
    /// `LSApplicationQueriesSchemes` in the iOS app's Info.plist, without which
    /// `canOpenURL` silently reports the DJ app as absent. The same literal
    /// lives in wxyc-dj-ios with no shared source; `DJAppLinkTests` pins it.
    public static let scheme = "wxycdj"

    /// The DJ-app link for a play's catalog album id, or `nil` when the play
    /// isn't catalog-linked (`albumId` nil or not a positive library id).
    public static func albumURL(albumId: Int?) -> URL? {
        guard let albumId, albumId > 0 else { return nil }
        return URL(string: "\(scheme)://album/\(albumId)")
    }
}
