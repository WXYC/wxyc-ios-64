//
//  WallpaperCardTests.swift
//  WXUI
//
//  Tests over WallpaperCard's canon stroke constants, its stroke-visibility
//  rule, and its stored geometry defaults — the pure logic behind the chrome.
//  The rendered view itself isn't inspectable without a snapshot/inspection
//  dependency this package deliberately doesn't take on, so these tests target
//  the values and decisions that drive it.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import WXUI

@Suite("WallpaperCard")
struct WallpaperCardTests {
    @Test("canon border opacity is 0.12")
    func borderOpacity() {
        #expect(WallpaperCard<Color, Color>.borderOpacity == 0.12)
    }

    @Test("canon border width is 1pt")
    func borderWidth() {
        #expect(WallpaperCard<Color, Color>.borderWidth == 1)
    }

    @Test("the hairline stroke shows only when stroked is true", arguments: [
        (true, true),
        (false, false),
    ])
    func strokeVisibility(stroked: Bool, expectedVisible: Bool) {
        #expect(WallpaperCard<Color, Color>.showsStroke(stroked: stroked) == expectedVisible)
    }

    @Test("default corner radius matches SongRowPanel's prior default of 12pt")
    func defaultCornerRadius() {
        let card = WallpaperCard(background: { Color.clear }, content: { Color.clear })
        #expect(card.cornerRadius == 12)
    }

    @Test("default stroked is false")
    func defaultStroked() {
        let card = WallpaperCard(background: { Color.clear }, content: { Color.clear })
        #expect(card.stroked == false)
    }

    @Test("an explicit corner radius and stroked flag are stored as given")
    func explicitValues() {
        let card = WallpaperCard(cornerRadius: 14, stroked: true, background: { Color.clear }, content: { Color.clear })
        #expect(card.cornerRadius == 14)
        #expect(card.stroked == true)
    }
}
