//
//  DetailCoverModifier.swift
//  WXYC
//
//  Platform seams for the app's full-screen detail presentations. `fullScreenCover`
//  doesn't exist on macOS, and the zoom navigation transition that ties a row to
//  the cover it opens is an iOS idiom — so these `View` extensions present the
//  platform's equivalent (a window-modal `sheet` on macOS) and collapse the zoom
//  chrome to identity there. Every detail cover and its zoom source route through
//  here, so the iOS tab views and a future native macOS navigation model share one
//  presentation vocabulary.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

extension View {
    /// Presents a detail screen as the platform's full-cover affordance: a
    /// `fullScreenCover` on iOS (which the tapped row zooms into) and a `sheet`
    /// on macOS, where `fullScreenCover` is unavailable and a window-modal sheet
    /// is the idiom.
    func detailCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS) || os(tvOS)
        return fullScreenCover(item: item, content: content)
        #else
        return sheet(item: item, content: content)
        #endif
    }

    /// The `isPresented` counterpart of `detailCover(item:)`, for a cover driven
    /// by a Boolean rather than an item (the party-horn celebration).
    func detailCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS) || os(tvOS)
        return fullScreenCover(isPresented: isPresented, content: content)
        #else
        return sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// The zoom navigation transition tying a presented detail back to the row
    /// that opened it (pair with `zoomTransitionSource(id:in:)`). Real on iOS;
    /// identity on macOS, where the detail arrives as a sheet rather than a zoom.
    func zoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS) || os(tvOS)
        return navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        #else
        return self
        #endif
    }

    /// Marks this view as the source a `zoomTransition` animates from. Real on
    /// iOS; identity on macOS.
    func zoomTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        #if os(iOS) || os(tvOS)
        return matchedTransitionSource(id: id, in: namespace)
        #else
        return self
        #endif
    }
}
