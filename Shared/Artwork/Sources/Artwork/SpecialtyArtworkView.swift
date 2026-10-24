//
//  SpecialtyArtworkView.swift
//  Artwork
//
//  The specialty program's square artwork: its logo, loaded through the shared
//  artwork cache, or the text tile drawn from its short name and accent color.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import CoreGraphics
import Caching
import Playlist
import SwiftUI

/// A network-free text tile for `program`. Fills the frame it is given, so an
/// `ImageRenderer` or a widget can draw it without any loading.
public struct SpecialtyTileView: View {
    private let program: SpecialtyShowRef

    public init(program: SpecialtyShowRef) {
        self.program = program
    }

    public var body: some View {
        let rgb = program.accentRGB
        ZStack {
            Rectangle().fill(rgb.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .gray)
            Text(program.tileText)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(4)
        }
    }
}

/// The program's logo at `size` x `size`, loaded through the shared artwork cache.
/// The tile occupies the same frame while loading, on failure, and when there is no logo,
/// so nothing shifts when the logo arrives.
public struct SpecialtyArtworkView: View {
    private let program: SpecialtyShowRef
    private let size: CGFloat
    @State private var logo: CGImage?
    @State private var state = SpecialtyArtwork.LogoState.loading

    public init(program: SpecialtyShowRef, size: CGFloat) {
        self.program = program
        self.size = size
    }

    public var body: some View {
        let url = SpecialtyArtwork.logoURL(for: program)
        ZStack {
            if SpecialtyArtwork.showsLogo(url: url, state: state), let logo {
                Image(decorative: logo, scale: 1).resizable().scaledToFill()
            } else if let bundled = SpecialtyArtwork.bundledLogo(for: program) {
                Image(decorative: bundled, scale: 1).resizable().scaledToFill()
            } else {
                SpecialtyTileView(program: program)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: url) {
            guard let url else { return }
            state = .loading
            do {
                logo = try await CacheCoordinator.AlbumArt.image(from: url)
                state = .loaded
            } catch {
                // A torn-down task is not a failed load; the view is going away or the task will rerun.
                if isCancellation(error) { return }
                state = .failed
            }
        }
    }
}
