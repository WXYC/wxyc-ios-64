//
//  TestTags.swift
//  AppServicesTests
//
//  Per-target Tag declarations for Swift Testing. Each test target is its
//  own Swift module, so the .ciHang tag is declared once per target.
//
//  Created by Jake Bromberg on 06/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing

extension Tag {
    /// Tests that hang on paravirtualized CI runners. An infrastructure gate,
    /// not a performance one: CI sets `WXYC_SKIP_CI_HANG=1` to exclude them;
    /// locally they run by default.
    @Tag static var ciHang: Self
}
