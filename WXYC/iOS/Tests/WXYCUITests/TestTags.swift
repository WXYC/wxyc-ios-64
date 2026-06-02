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
    /// Tests that take longer than a second on a baseline reference machine.
    /// CI sets `WXYC_SKIP_SLOW=1` to exclude them; locally they run by default
    /// unless the same env var is set. See `.disabled(if:)` traits on tagged
    /// suites/tests for the gating mechanism.
    @Tag static var slow: Self
}
