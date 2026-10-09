//
//  DJAppLinkTests.swift
//  Playlist
//
//  Pins the `wxycdj://album/<id>` link the playcut detail's "Open in WXYC DJ"
//  button opens. The scheme literal also lives in wxyc-dj-ios with no shared
//  source, so this table is what catches the two drifting apart (#1151).
//
//  Created by Jake Bromberg on 10/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist

@Suite("DJAppLink Tests")
struct DJAppLinkTests {

    @Test(
        "albumURL builds wxycdj://album/<id> for a catalog-linked play and nil otherwise",
        arguments: [
            (4417 as Int?, "wxycdj://album/4417" as String?),
            (1, "wxycdj://album/1"),
            (nil, nil),
            (0, nil),
            (-5, nil),
        ]
    )
    func albumURL(albumId: Int?, expected: String?) {
        #expect(DJAppLink.albumURL(albumId: albumId)?.absoluteString == expected)
    }
}
