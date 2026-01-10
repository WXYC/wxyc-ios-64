//
//  WXYCMeshAnimation.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/25/25.
//

import SwiftUI

/// WXYC-branded animated mesh gradient.
///
/// A convenience wrapper around `AnimatedMeshGradient` with pre-generated colors.
/// Use this for consistent branding across the app.
public struct WXYCMeshAnimation: View {
    private let gradient: AnimatedMeshGradient

    public init() {
        self.gradient = AnimatedMeshGradient()
    }

    public var body: some View {
        gradient
    }
}

// MARK: - ShapeStyle Conformance

extension WXYCMeshAnimation: ShapeStyle {}
