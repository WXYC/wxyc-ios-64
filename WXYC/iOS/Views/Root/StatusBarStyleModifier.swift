//
//  StatusBarStyleModifier.swift
//  WXYC
//
//  Created to ensure status bar is always light content
//
//  Created by Jake Bromberg on 12/14/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

extension View {
    /// Pins the window to a dark color scheme so the status bar always renders
    /// light (white) content, matching the app's white-on-wallpaper text.
    ///
    /// Scene-based apps ignore the Info.plist `UIStatusBarStyle` /
    /// `UIViewControllerBasedStatusBarAppearance` pair; the status bar follows
    /// the hosting controller's color scheme, so this is the supported override.
    func forceLightStatusBar() -> some View {
        preferredColorScheme(.dark)
    }
}
