//
//  AdaptiveRootView.swift
//  WXYC
//
//  Adaptive root view that branches between the compact phone layout (RootTabView)
//  and a NavigationSplitView-based layout for regular horizontal size class (iPad, Mac).
//
//  Created by Jake Bromberg on 04/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            RootTabView()
        } else {
            RegularLayoutView()
        }
    }
}
