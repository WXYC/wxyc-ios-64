//
//  TestTags.swift
//  PartyHorn
//
//  Swift Testing tag declarations for PartyHornTests.
//
//  Created by Jake Bromberg on 06/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing

// MARK: - Test Tags

extension Tag {
    /// Tests that take longer than a second on a baseline reference machine, or
    /// that hang on paravirtualized CI runners (e.g. SoundPlayerTests blocks
    /// indefinitely activating AVAudioSession when there's no real audio
    /// hardware). CI sets `WXYC_SKIP_SLOW=1` to exclude them; locally they run
    /// by default.
    @Tag static var slow: Self
}
