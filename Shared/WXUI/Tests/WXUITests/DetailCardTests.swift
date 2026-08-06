//
//  DetailCardTests.swift
//  WXUI
//
//  Tests over DetailCard's canon constants and header-visibility rule — the
//  pure logic behind the chrome. The rendered view itself isn't inspectable
//  without a snapshot/inspection dependency this package deliberately doesn't
//  take on, so these tests target the values and decisions that drive it.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import WXUI

@Suite("DetailCard")
struct DetailCardTests {
    @Test("canon corner radius is 16pt")
    func cornerRadius() {
        #expect(DetailCard<EmptyView>.cornerRadius == 16)
    }

    @Test("canon fill opacity is 0.1")
    func fillOpacity() {
        #expect(DetailCard<EmptyView>.fillOpacity == 0.1)
    }

    @Test("a title shows the header; no title omits it", arguments: [
        (Optional("More Info"), true),
        (nil, false),
    ] as [(String?, Bool)])
    func headerVisibility(title: String?, expectedVisible: Bool) {
        #expect(DetailCard<EmptyView>.showsHeader(title: title) == expectedVisible)
    }
}
