//
//  OnAirBannerView.swift
//  WXYC
//
//  Persistent banner that promotes the current DJ's sign-on to the top of the playlist.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreText
import Playlist
import SwiftUI

/// A banner surfacing the DJ currently on the air (or "Auto DJ") at the top of the playlist.
///
/// A white "ON AIR" eyebrow with a themed live indicator sits above the DJ's handle, rendered
/// directly over the wallpaper with no card chrome. The indicator color/glow, the handle's SF
/// Pro variable-font axes, and the vertical spacing all come from ``OnAirBannerTheme`` so the
/// debug controls can tune them live; ``OnAirBannerTheme/default`` is the shipping look.
struct OnAirBannerView: View {
    /// The DJ's name, e.g. "DJ HOUNDSTOOTH", or "Auto DJ" when nobody is signed on.
    let headline: String

    /// Tunable design parameters: indicator color/glow, handle font variation, and spacing.
    var theme: OnAirBannerTheme = .default

    /// When set, tapping the banner invokes this — used to present the debug controls sheet.
    /// `nil` in release, so the banner is inert.
    var onDebugTapped: (() -> Void)? = nil

    var body: some View {
        if let onDebugTapped {
            Button(action: onDebugTapped) { banner }
                .buttonStyle(.plain)
        } else {
            banner
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                OnAirIndicator(size: 8, color: theme.indicatorColor, blurRadius: theme.indicatorBlurRadius)

                Text("ON AIR")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(.white)
            }

            Text(headline)
                .font(handleFont)
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .lineSpacing(theme.handleLineSpacing)
                .padding(.top, theme.onAirSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On air. \(headline)")
    }

    /// The DJ handle rendered across SF Pro's four variable-font axes from the theme.
    ///
    /// SwiftUI exposes only discrete `Font.Weight`, so we set the raw
    /// `kCTFontVariationAttribute` on a copy of the system font to drive weight, width,
    /// optical size, and grade continuously, then bridge the `CTFont` into SwiftUI.
    private var handleFont: Font {
        let base = CTFontCreateUIFontForLanguage(.system, 24, nil)
            ?? CTFontCreateWithName("SFPro-Regular" as CFString, 24, nil)
        let attributes: [CFString: Any] = [kCTFontVariationAttribute: theme.handleVariation.variationDictionary]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let varied = CTFontCreateCopyWithAttributes(base, 24, nil, descriptor)
        return Font(varied)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            OnAirBannerView(headline: "DJ HOUNDSTOOTH")
            OnAirBannerView(headline: "Auto DJ")
        }
        .padding()
    }
    .background(.black)
}
