//
//  ContentColumn.swift
//  WXYC
//
//  Caps a tab's scroll content at `maxWidth` and centers it, so cards, banners,
//  and tips compose on iPad and wide Mac windows instead of stretching to the
//  window. The container clips nothing: the wallpaper behind it shows through
//  the side gutters. The cap and the iPhone reference width are exported for the
//  LCD bar-count policy and the two-column breakpoint.
//
//  Created by Jake Bromberg on 10/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

enum ContentColumn {
    /// The widest the content column grows. Experiment default; must exceed
    /// `referenceWidth` so the LCD split can engage.
    static let maxWidth: CGFloat = 600

    /// The iPhone 17 Pro Max logical width the layouts are designed against.
    static let referenceWidth: CGFloat = 440

    /// The column width for a container `available` points wide.
    static func effectiveWidth(available: CGFloat) -> CGFloat {
        min(available, maxWidth)
    }
}

extension View {
    /// Constrains this view to the content column, centered in its container.
    func contentColumn() -> some View {
        frame(maxWidth: ContentColumn.maxWidth)
            .frame(maxWidth: .infinity)
    }
}
