//
//  TabBarTransparency.swift
//  WXYC
//
//  Makes the standard tab bar's backing transparent so the Metal wallpaper,
//  rendered behind RootTabView in ThemePickerContainer, shows through.
//
//  The `Tab` API is backed by UITabBarController, whose view defaults to an
//  opaque systemBackground. Left alone it paints white over the wallpaper. A
//  zero-size probe walks up to the enclosing tab controller and clears the
//  opaque backings so the wallpaper shows through.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Clear logic

@MainActor
enum TabBarBackgroundClearer {
    /// Walks up from `view`, clearing each opaque background until it clears the
    /// enclosing `UITabBarController`'s view (inclusive) plus every child view
    /// controller's view. Returns the controller it cleared, or `nil` when the
    /// view is not yet inside a tab controller.
    @discardableResult
    static func clearBackgrounds(from view: UIView) -> UITabBarController? {
        var current: UIView? = view
        while let candidate = current {
            candidate.backgroundColor = .clear
            if let controller = candidate.next as? UITabBarController {
                for child in controller.viewControllers ?? [] {
                    child.viewIfLoaded?.backgroundColor = .clear
                }
                return controller
            }
            current = candidate.superview
        }
        return nil
    }
}

// MARK: - SwiftUI probe

/// A zero-size background probe that clears the enclosing tab controller's
/// opaque backing as it lands in the window.
struct TabBarTransparencyProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Clear in the turn that put this view in the window, so no frame
            // commits with the backing still painted. A clear that waits even
            // one main-actor hop races the first frame, and when it loses the
            // launch flashes systemBackground over the wallpaper. The status
            // bar pays for it too: its glyph color is settled by what is on
            // screen in the window's first moments and holds until the scene
            // next reactivates, so a flash that lasts long enough leaves dark
            // glyphs on the wallpaper for the rest of the session.
            TabBarBackgroundClearer.clearBackgrounds(from: self)
            // And again one hop later, for anything SwiftUI installs after this
            // turn. On iOS 27 the pass above already reaches the tab controller
            // and nothing repaints it; this one stays because that has not been
            // checked back to the 18.6 floor.
            Task { @MainActor [weak self] in
                guard let self else { return }
                TabBarBackgroundClearer.clearBackgrounds(from: self)
            }
        }
    }
}

extension View {
    /// Clears the enclosing tab bar controller's opaque backing so content
    /// rendered behind the tab view (the Metal wallpaper) shows through.
    func clearTabBarBackground() -> some View {
        background(TabBarTransparencyProbe())
    }
}
#endif
