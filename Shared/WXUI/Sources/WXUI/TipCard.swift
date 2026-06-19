//
//  TipCard.swift
//  WXUI
//
//  Shared card chrome for tips and status banners.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// The shared card chrome used by contextual tips and status banners: a custom
/// background, rounded corners, and standard internal padding.
///
/// `TipView` and the playlist's on-air banner both compose this so they render as
/// the same cell type. Transitions are intentionally left to the caller, so each
/// consumer controls its own insertion/removal animation.
public struct TipCard<Content: View, Background: View>: View {
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    public init(
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.background = background
        self.content = content
    }

    public var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background { background() }
            .clipShape(.rect(cornerRadius: 16))
    }
}
