//
//  WallpaperCardView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Cross-platform image conversion
extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

/// A card view that displays either a live wallpaper or a static snapshot.
/// When transitioning from snapshot to live, performs a crossfade animation.
struct WallpaperCardView: View {
    let wallpaper: LoadedWallpaper
    let isLive: Bool
    let snapshot: WallpaperSnapshot?
    let cardSize: CGSize
    let cornerRadius: CGFloat

    /// Opacity for the snapshot overlay during crossfade transition.
    @State private var snapshotOverlayOpacity: CGFloat = 1.0

    /// Duration of the crossfade from snapshot to live.
    private let crossfadeDuration: TimeInterval = 0.2

    var body: some View {
        VStack(spacing: 12) {
            // Wallpaper name label above the card
            Text(wallpaper.displayName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            // Wallpaper card
            ZStack {
                if isLive {
                    // Live wallpaper renderer
                    WallpaperRendererFactory.makeView(for: wallpaper)

                    // Crossfade overlay: show snapshot briefly when transitioning to live
                    if let snapshot, snapshotOverlayOpacity > 0 {
                        Image(platformImage: snapshot.image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(snapshotOverlayOpacity)
                    }
                } else if let snapshot {
                    // Static snapshot
                    Image(platformImage: snapshot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Placeholder while snapshot is being generated
                    placeholderView
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .onChange(of: isLive) { wasLive, nowLive in
            if nowLive && !wasLive {
                // Transitioning from snapshot to live: start crossfade
                snapshotOverlayOpacity = 1.0
                withAnimation(.easeOut(duration: crossfadeDuration)) {
                    snapshotOverlayOpacity = 0
                }
            } else if !nowLive && wasLive {
                // Transitioning from live to snapshot: reset overlay
                snapshotOverlayOpacity = 1.0
            }
        }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.black)
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text(wallpaper.displayName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
    }
}
