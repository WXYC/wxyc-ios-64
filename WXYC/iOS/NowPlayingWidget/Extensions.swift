//
//  Extensions.swift
//  WXYC
//
//  Utility extensions for widget implementation.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - Image Extensions

extension SwiftUI.Image {
    static var logo: some View {
        ZStack {
            Rectangle()
                .background(.white)
                .background(.ultraThinMaterial)
                .opacity(0.2)
            Image(ImageResource(name: "logo_small", bundle: .main))
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(.white)
                .opacity(0.75)
                .blendMode(.colorDodge)
                .scaleEffect(0.85)
        }
        .aspectRatio(contentMode: .fit)
        .cornerRadius(10)
        .clipped()
    }
    
    static var background: some View {
        ZStack {
            Image(ImageResource(name: "background", bundle: .main))
                .resizable()
                .opacity(0.95)
            Rectangle()
                .foregroundStyle(.gray)
                .background(.gray)
                .background(.ultraThickMaterial)
                .opacity(0.18)
                .blendMode(.colorBurn)
                .saturation(0)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Artwork Fallback

/// Renders `artwork` when present, or `fallback()` otherwise — the branch
/// every widget artwork slot (`Header`, `RecentlyPlayedRow`, and the
/// `NowPlayingWidgetEntryView` protocol default) needs when a played track has
/// no cached image yet. Each of the three call sites frames and
/// corner-radiuses the loaded artwork (and, in two of the three, the fallback
/// logo) differently, so both branches are supplied as builder closures rather
/// than baking one fixed size/style into the helper.
@ViewBuilder
func artworkOrLogo<Loaded: View, Fallback: View>(
    _ artwork: SwiftUI.Image?,
    @ViewBuilder loaded: (SwiftUI.Image) -> Loaded,
    @ViewBuilder fallback: () -> Fallback
) -> some View {
    if let artwork {
        loaded(artwork)
    } else {
        fallback()
    }
}

// MARK: - Collection Async

extension Collection where Self: Sendable, Element: Sendable {
    /// Asynchronously maps each element of the collection using the given transform.
    /// Elements are processed concurrently using a task group, preserving input order.
    public func asyncMap<T: Sendable>(_ transform: @Sendable @escaping (Element) async -> T) async -> [T] {
        let indexed = Array(self.enumerated())
        return await withTaskGroup(of: (Int, T).self) { group in
            for (index, element) in indexed {
                group.addTask {
                    (index, await transform(element))
                }
            }

            var results = Array<T?>(repeating: nil, count: indexed.count)
            for await (index, value) in group {
                results[index] = value
            }

            return results.compactMap { $0 }
        }
    }
}

// MARK: - ShapeStyle Colors

extension ShapeStyle where Self == Color {
    static var darken: Color {
        Color(white: 0, opacity: 0.25)
    }

    static var lighten: Color {
        Color(white: 1, opacity: 0.25)
    }
}
