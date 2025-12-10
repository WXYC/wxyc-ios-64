//
//  GlassEffect+Compatibility.swift
//  WXUI
//
//  Provides backwards-compatible wrappers for the iOS 26+ glassEffect modifier.
//  On earlier OS versions, these methods simply return the view unchanged.
//

import SwiftUI

// MARK: - Compatibility View Modifiers

extension View {
    /// Applies a clear glass effect, falling back gracefully on earlier OS versions.
    @ViewBuilder
    public func glassEffectClearIfAvailable() -> some View {
        if #available(iOS 26, watchOS 26, tvOS 26, visionOS 26, macOS 26, *) {
            self.glassEffect(.clear)
        } else {
            self
        }
    }
    
    /// Applies a clear glass effect with a shape, falling back gracefully on earlier OS versions.
    @ViewBuilder
    public func glassEffectClearIfAvailable<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, watchOS 26, tvOS 26, visionOS 26, macOS 26, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self
        }
    }
    
    /// Applies a regular glass effect with a shape, falling back gracefully on earlier OS versions.
    @ViewBuilder
    public func glassEffectRegularIfAvailable<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, watchOS 26, tvOS 26, visionOS 26, macOS 26, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self
        }
    }
    
    /// Applies a glass effect with just a shape (default style), falling back gracefully on earlier OS versions.
    @ViewBuilder
    public func glassEffectIfAvailable<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, watchOS 26, tvOS 26, visionOS 26, macOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self
        }
    }
    
    /// Applies an interactive tinted clear glass effect with a shape, falling back gracefully on earlier OS versions.
    @ViewBuilder
    public func glassEffectClearTintedInteractiveIfAvailable<S: Shape>(tint: Color, in shape: S) -> some View {
        if #available(iOS 26, watchOS 26, tvOS 26, visionOS 26, macOS 26, *) {
            self.glassEffect(.clear.tint(tint).interactive(), in: shape)
        } else {
            self
        }
    }
}
