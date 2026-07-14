//
//  TabBarBackgroundClearerTests.swift
//  WXYC
//
//  The standard `Tab` API is backed by UITabBarController, whose view defaults
//  to an opaque systemBackground. That opaque layer sits in front of the Metal
//  wallpaper (rendered behind RootTabView) and hides it. These tests pin the
//  hierarchy-walking clear that punches the tab controller's backing back to
//  transparent so the wallpaper shows through and the long-press picker's
//  touches still reach the content.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import UIKit
@testable import WXYC

@MainActor
@Suite("TabBarBackgroundClearer")
struct TabBarBackgroundClearerTests {
    /// Builds a probe view nested inside a tab controller's selected child,
    /// with every background set opaque so the clear is observable.
    private func makeHierarchy() -> (tab: UITabBarController, child: UIViewController, probe: UIView) {
        let tab = UITabBarController()
        let child = UIViewController()
        tab.viewControllers = [child]
        tab.loadViewIfNeeded()
        child.loadViewIfNeeded()
        tab.view.addSubview(child.view)

        let probe = UIView()
        child.view.addSubview(probe)

        for view in [tab.view, child.view, probe] {
            view?.backgroundColor = .systemBackground
        }
        return (tab, child, probe)
    }

    @Test("Clears the enclosing tab controller's backing and returns it")
    func clearsTabControllerBacking() {
        let (tab, _, probe) = makeHierarchy()
        let found = TabBarBackgroundClearer.clearBackgrounds(from: probe)
        #expect(found === tab)
        #expect(tab.view.backgroundColor == .clear)
    }

    @Test("Clears opaque views along the path up to the controller")
    func clearsPathViews() {
        let (_, child, probe) = makeHierarchy()
        TabBarBackgroundClearer.clearBackgrounds(from: probe)
        #expect(probe.backgroundColor == .clear)
        #expect(child.view.backgroundColor == .clear)
    }

    @Test("Clears every child view controller's view, not just the selected one")
    func clearsAllChildViews() {
        let (tab, _, probe) = makeHierarchy()
        let second = UIViewController()
        tab.viewControllers = [tab.viewControllers![0], second]
        second.loadViewIfNeeded()
        second.view.backgroundColor = .systemBackground

        TabBarBackgroundClearer.clearBackgrounds(from: probe)
        #expect(second.view.backgroundColor == .clear)
    }

    @Test("Returns nil and clears nothing fatal when no tab controller is present")
    func noTabControllerIsSafe() {
        let orphan = UIView()
        orphan.backgroundColor = .systemBackground
        let found = TabBarBackgroundClearer.clearBackgrounds(from: orphan)
        #expect(found == nil)
    }
}
