//
//  TestTags.swift
//  WXYC
//
//  Swift Testing tag declarations for WXYCUITests.
//
//  Created by Jake Bromberg on 06/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing

// MARK: - Test Tags

extension Tag {
    /// End-to-end XCUITest suites. These are minutes-long (driving the real app
    /// through the simulator) and are the dominant CI-minute cost, so CI excludes
    /// them — both at the target level (`-skip-testing:WXYCUITests`) and via this
    /// gate as belt-and-suspenders. CI sets `WXYC_SKIP_UI=1`; locally they run by
    /// default unless the same env var is set. See `.disabled(if:)` traits on
    /// tagged suites/tests for the gating mechanism.
    @Tag static var uiTest: Self
}
