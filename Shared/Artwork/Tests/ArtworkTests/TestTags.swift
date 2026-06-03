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
    /// Tests that take longer than a second on a baseline reference machine, or
    /// that hang/stall on paravirtualized CI runners (e.g. GitHub Actions macOS
    /// images, where the `ArtworkTests` bundle starts and produces zero results
    /// within the job timeout — see PR description for the paravirt hang).
    /// CI sets `WXYC_SKIP_SLOW=1` to exclude them; locally they run by default.
    @Tag static var slow: Self
}
