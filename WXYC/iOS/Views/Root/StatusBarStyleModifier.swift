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

// Custom UIHostingController that forces light status bar
class LightStatusBarHostingController<Content: View>: UIHostingController<Content> {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsStatusBarAppearanceUpdate()
    }
}

// Custom Scene that uses LightStatusBarHostingController
struct LightStatusBarWindowGroup<Content: View>: Scene {
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some Scene {
        WindowGroup {
            content()
                .onAppear {
                    // Force status bar update on appear
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        rootViewController.setNeedsStatusBarAppearanceUpdate()
                    }
                }
        }
    }
}

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
