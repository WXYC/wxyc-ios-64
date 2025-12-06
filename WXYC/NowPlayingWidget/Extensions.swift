//
//  Extensions.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import SwiftUI

// MARK: - RangeReplaceableCollection

extension RangeReplaceableCollection {
    mutating func popFirst() -> (Element, Self) {
        let first = removeFirst()
        return (first, self)
    }
}

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

// MARK: - Collection Async

extension Collection where Self: Sendable, Element: Sendable {
    /// Asynchronously maps each element of the collection using the given transform.
    /// Elements are processed concurrently using a task group.
    public func asyncMap<T: Sendable>(_ transform: @Sendable @escaping (Element) async -> T) async -> [T] {
        await withTaskGroup(of: T.self) { group in
            for element in self {
                group.addTask {
                    await transform(element)
                }
            }
            
            var results: [T] = []
            for await result in group {
                results.append(result)
            }
            
            return results
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

