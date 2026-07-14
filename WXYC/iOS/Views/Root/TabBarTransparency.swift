//
//  TabBarTransparency.swift
//  WXYC
//
//  Makes the standard tab bar's backing transparent so the Metal wallpaper,
//  rendered behind RootTabView in ThemePickerContainer, shows through.
//
//  The `Tab` API is backed by UITabBarController, whose view defaults to an
//  opaque systemBackground. Left alone it paints white over the wallpaper and
//  swallows the long-press that opens the theme picker. This mirrors the
//  Wallpaper package's ScrollViewIntrospector: a zero-size probe walks up to
//  the enclosing tab controller and clears the opaque backings.
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
/// opaque backing once it lands in the window.
struct TabBarTransparencyProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ uiView: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Defer one main-actor hop so SwiftUI finishes installing the tab
            // controller's view tree before we walk it.
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
