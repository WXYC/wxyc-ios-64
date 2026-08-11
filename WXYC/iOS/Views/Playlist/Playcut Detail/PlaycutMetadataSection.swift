//
//  PlaycutMetadataSection.swift
//  WXYC
//
//  Detailed metadata section (label, catalog#, etc.).
//
//  Created by Jake Bromberg on 12/06/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Metadata
import Playlist
import WXUI

struct PlaycutMetadataSection: View {
    let metadata: PlaycutMetadata
    @Binding var expandedBio: Bool

    private var tags: [String] {
        (metadata.album.genres ?? []) + (metadata.album.styles ?? [])
    }

    var body: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 16) {
                // Label and Year
                Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 10) {
                    if let label = metadata.label {
                        GridRow {
                            MetadataLabel(title: "Label")
                            MetadataValue(value: DiscogsMarkupParser.stripDisambiguationSuffix(from: label))
                        }
                    }
                    if let year = metadata.releaseYear {
                        GridRow {
                            MetadataLabel(title: "Year")
                            HStack {
                                MetadataValue(value: String(year))
                                Spacer()
                            }
                        }
                    }
                }

                // Genre/Style Tags
                if !tags.isEmpty {
                    GenreTagsView(tags: tags)
                }

                // "Not on Discogs" (#390) — the MD flag that also suppresses the
                // artwork above. The note is optional free text; when absent, the
                // label alone still tells the listener why artwork is missing
                // instead of leaving it unexplained.
                if metadata.album.isDiscogsUnavailable {
                    Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 10) {
                        GridRow {
                            MetadataLabel(title: "Discogs")
                            MetadataValue(value: metadata.album.discogsUnavailableNote ?? "Not on Discogs")
                        }
                    }
                }

                // Artist Bio
                if let bio = metadata.artistBio, !bio.isEmpty {
                    ArtistBioSection(bio: bio, bioTokens: metadata.artist.bioTokens, expandedBio: $expandedBio)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var expandedBio = false
    @Previewable @State var isShowingLightbox = false
    @Previewable @Namespace var previewNamespace

    // The album block and the header's playcut have to describe the *same*
    // release — this preview stacks them, so a mismatched label reads as a real
    // (and wrong) record rather than as fixture data.
    let metadata = PlaycutMetadata(
        artist: .empty,
        album: AlbumMetadata(
            label: "Drag City",
            releaseYear: 2015,
            genres: ["Rock"],
            styles: ["Folk Rock", "Acoustic"]
        ),
        streaming: .empty
    )

    PlaycutLoadingSection()

    // Built through `Playcut.init` rather than `Playcut.stub()`: the app target
    // doesn't link `PlaylistTesting`. See `PreviewFixtures` for why, and
    // `docs/test-fixtures.md` for the canonical values used here.
    PlaycutHeaderSection(
        playcut: Playcut(
            id: 0,
            hour: 0,
            chronOrderID: 0,
            timeCreated: 0,
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        ),
        artwork: nil,
        isLightboxActive: $isShowingLightbox,
        hideArtwork: false,
        artworkNamespace: previewNamespace,
        artworkGeometryID: "preview-artwork",
        onArtworkTap: {}
    )

    PlaycutMetadataSection(
        metadata: metadata,
        expandedBio: $expandedBio
    )

    ExternalLinksSection(metadata: metadata)
}
