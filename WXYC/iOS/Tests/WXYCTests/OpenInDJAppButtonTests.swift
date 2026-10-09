//
//  OpenInDJAppButtonTests.swift
//  WXYC
//
//  The "Open in WXYC DJ" button's visibility rule, and the Info.plist entry it
//  silently depends on: `canOpenURL` answers `false` for any scheme missing
//  from `LSApplicationQueriesSchemes`, so dropping `wxycdj` there would hide
//  the button for everyone with no other failure.
//
//  Created by Jake Bromberg on 10/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist
import Testing
@testable import WXYC

@Suite("OpenInDJAppButton")
@MainActor
struct OpenInDJAppButtonTests {
    @Test(
        "shows for a catalog-linked play only when the DJ app can be opened",
        arguments: [
            (4417 as Int?, true, "wxycdj://album/4417" as String?),
            (4417, false, nil),
            (nil, true, nil),
        ]
    )
    func visibility(albumId: Int?, canOpen: Bool, expected: String?) {
        let url = OpenInDJAppButton.openableURL(albumId: albumId, canOpen: { _ in canOpen })
        #expect(url?.absoluteString == expected)
    }

    @Test("Info.plist lets canOpenURL query the DJ app's scheme")
    func infoPlistListsTheScheme() {
        // WXYCTests is host-app-tested (TEST_HOST = WXYC.app), so Bundle.main
        // is the app.
        let schemes = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String]
        #expect(schemes?.contains(DJAppLink.scheme) == true)
    }
}
