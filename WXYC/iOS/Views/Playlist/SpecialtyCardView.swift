//
//  SpecialtyCardView.swift
//  WXYC
//
//  The specialty program's card: its logo (or a text tile drawn from its short
//  name and accent color), its name, a subtitle, and the tagline while no song
//  or who's-on entry has landed.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Artwork
import Playlist
import SwiftUI
import Wallpaper
import WXUI

/// Lays out the card's two children, the artwork slot and the text column, in a
/// row whose slot is a playcut row's: `SongRowMetrics.artworkSlotWidth` of the
/// width the card is proposed, so the logo is the playcut artwork's size from the
/// first layout pass, on any device and in any window. The height is the taller
/// of the square slot and the text, so the text is never cut off and no height
/// is fixed. Both children are top-aligned.
struct SpecialtyCardLayout: Layout {
    /// The width a card lays out at when its parent proposes none.
    nonisolated static let fallbackWidth: CGFloat = ContentColumn.maxWidth

    /// The slot's width, which is also its height, and the text column's width
    /// in a card `width` points wide.
    nonisolated static func columnWidths(forCardWidth width: CGFloat) -> (slot: CGFloat, text: CGFloat) {
        let slot = SongRowMetrics.artworkSlotWidth(rowWidth: width)
        return (slot, max(width - slot, 0))
    }

    /// `proposed`, or the fallback when it is nil or infinite, so the text width is never NaN.
    nonisolated static func resolvedWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return fallbackWidth }
        return proposed
    }

    /// The card's height in a card `width` points wide whose text is `textHeight` tall.
    nonisolated static func cardHeight(forCardWidth width: CGFloat, textHeight: CGFloat) -> CGFloat {
        max(columnWidths(forCardWidth: width).slot, textHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = Self.resolvedWidth(proposal.width)
        let columns = Self.columnWidths(forCardWidth: width)
        let textHeight = subviews[1].sizeThatFits(ProposedViewSize(width: columns.text, height: nil)).height
        return CGSize(width: width, height: Self.cardHeight(forCardWidth: width, textHeight: textHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let columns = Self.columnWidths(forCardWidth: bounds.width)
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: columns.slot, height: columns.slot)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + columns.slot, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: columns.text, height: bounds.height)
        )
    }
}

struct SpecialtyCardView: View {
    let card: SpecialtyCard

    private static let cornerRadius = SongRowMetrics.cornerRadius

    @State private var shadowYOffset: CGFloat = 0

    var body: some View {
        WallpaperCard(cornerRadius: Self.cornerRadius) {
            BackgroundLayer(cornerRadius: Self.cornerRadius)
        } content: {
            SpecialtyCardLayout {
                RowArtworkSlot {
                    RowArtworkFrame(shadowYOffset: shadowYOffset) {
                        SpecialtyArtworkView(program: card.program)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.program.name)
                        .font(.headline)
                    if let subtitle = card.showName {
                        Text(subtitle)
                            .font(.subheadline)
                    }
                    Text(card.djHandle)
                        .font(.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    if let nowLine = card.nowLine {
                        Text(nowLine)
                            .font(.subheadline.weight(.semibold))
                    }
                    if card.showsTagline, let tagline = card.program.tagline {
                        Text(tagline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.white)
                .padding(.vertical, SongRowMetrics.artworkPadding)
                .padding(.trailing, SongRowMetrics.artworkPadding)
            }
        }
        .modifier(ScrollShadowModifier(shadowYOffset: $shadowYOffset, top: SongRowMetrics.shadowOffsetAtTop, bottom: SongRowMetrics.shadowOffsetAtBottom))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("playlist.specialtyCard")
    }
}

#Preview {
    VStack {
        SpecialtyCardView(card: SpecialtyCard(
            program: SpecialtyShowRef(id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW", tagline: "Weird and wonderful", accentColor: "#B3261E"),
            showName: "Hogwash Hour",
            djHandle: "DJ Monster",
            placement: .aboveSongList,
            showsTagline: true,
            showsNowPlayingHeader: false
        ))
    }
    .padding()
    .background(.black)
}
