//
//  TestTags.swift
//  Artwork
//
//  Swift Testing tag declarations for ArtworkTests.
//
//  Created by Jake Bromberg on 06/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing

// MARK: - Test Tags

extension Tag {
    /// Tests that hang or stall on paravirtualized CI runners (e.g. GitHub
    /// Actions macOS images, where the `ArtworkTests` bundle starts and produces
    /// zero results within the job timeout — see PR description for the paravirt
    /// hang). This is an infrastructure-incompatibility gate, not a performance
    /// one: CI sets `WXYC_SKIP_CI_HANG=1` to exclude them; locally they run by
    /// default (real hardware doesn't exhibit the hang).
    @Tag static var ciHang: Self
}
