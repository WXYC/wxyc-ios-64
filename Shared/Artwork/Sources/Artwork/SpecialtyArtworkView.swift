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

/// Draws `content` filling a square slot: the square is as large as the proposal
/// allows (its shorter side), and `content` is cropped to it, so an image of any
/// aspect ratio can never report a size larger than its slot.
struct SquareFill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipped()
    }
}

/// The program's logo at `size` x `size` (or, with no size, filling the square
/// its parent proposes), loaded through the shared artwork cache.
/// The tile occupies the same frame while loading, on failure, and when there is no logo,
/// so nothing shifts when the logo arrives.
public struct SpecialtyArtworkView: View {
    private let program: SpecialtyShowRef
    private let size: CGFloat?
    private let resolve: @Sendable (SpecialtyShowRef) async -> CGImage?
    @State private var logo: CGImage?

    public init(program: SpecialtyShowRef, size: CGFloat) {
        self.init(program: program, size: size, resolve: { await SpecialtyArtwork.logo(for: $0) })
    }

    /// The artwork fills the frame its parent proposes, so a custom `Layout`
    /// can size it without the view knowing the number.
    public init(program: SpecialtyShowRef) {
        self.init(program: program, size: nil, resolve: { await SpecialtyArtwork.logo(for: $0) })
    }

    /// `resolve` is injected so a test can count resolutions.
    init(program: SpecialtyShowRef, size: CGFloat?, resolve: @escaping @Sendable (SpecialtyShowRef) async -> CGImage?) {
        self.program = program
        self.size = size
        self.resolve = resolve
    }

    /// The sized init pins the frame; the size-less init fills the proposed square.
    @ViewBuilder
    private func sized<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if let size {
            ZStack { content() }
                .frame(width: size, height: size)
                .clipped()
        } else {
            SquareFill { ZStack { content() } }
        }
    }

    /// Renders only state: the tile until the task resolves a logo.
    public var body: some View {
        sized {
            if let logo {
                Image(decorative: logo, scale: 1).resizable().scaledToFill()
            } else {
                SpecialtyTileView(program: program)
            }
        }
        .task(id: program) {
            logo = nil
            let resolved = await resolve(program)
            // A cancelled task is not a failure: leave the state for the rerun.
            if Task.isCancelled { return }
            logo = resolved
        }
    }
}
