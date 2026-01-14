//
//  ThemeDebugOverlay.swift
//  Wallpaper
//
//  Floating button overlay that presents theme debug controls in a popover.
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// Floating button overlay for theme debug controls.
/// Shows a button in the bottom-right corner that presents a popover with
/// theme selection and parameter controls.
public struct ThemeDebugOverlay: View {
    @Bindable var configuration: ThemeConfiguration
    @State private var showingPopover = false

    public init(configuration: ThemeConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showingPopover = true
                } label: {
                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                #if os(tvOS)
                .sheet(isPresented: $showingPopover) {
                    ThemeDebugPopoverContent(configuration: configuration)
                }
                #else
                .popover(isPresented: $showingPopover) {
                    ThemeDebugPopoverContent(configuration: configuration)
                }
                #endif
            }
        }
        .padding()
    }
}
#endif
