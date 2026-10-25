//
//  SpotlightRoleCopyTests.swift
//  Playlist
//
//  Verifies the one role table: each raw role string yields both its on-screen label and its spoken activity.
//
//  Created by Jake Bromberg on 10/25/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

struct SpotlightRoleCopyTests {
    @Test("Role copy", arguments: [
        ("guest", "In the studio", "in the studio"),
        ("performer", "Live in the studio", "playing live in the studio"),
        ("reader", "Reading now", "reading"),
        ("dj", "Now mixing", "mixing"),
        ("host", nil, nil),
        ("interpretive dancer", "On air", nil),
    ] as [(String, String?, String?)])
    func roleCopy(role: String, label: String?, activity: String?) {
        let entry = SpotlightEntry.stub(id: 1, role: role, name: "Weirs")
        #expect(entry.roleLabel == label)
        #expect(entry.spokenActivity == activity)
    }
}
