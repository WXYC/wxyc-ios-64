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
import UIKit

extension View {
    func forceLightStatusBar() -> some View {
        self.onAppear {
            // Update status bar style when view appears
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }
}
