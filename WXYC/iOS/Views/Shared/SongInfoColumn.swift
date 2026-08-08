//
//  SongInfoColumn.swift
//  WXYC
//
//  The title / artist / detail text column shared by the flowsheet row
//  (`PlaycutRowView`), the Liked tab row (`LikedSongRow`), and the
//  NowPlayingWidget's rows (`Header`, `MediumNowPlayingWidgetEntryView`,
//  `RecentlyPlayedRow`, `SmallNowPlayingWidgetEntryView`). All feed it any
//  `SongDisplayable`, so a song's title and artist render identically across
//  every surface; the third line — the flowsheet's play time vs. the Liked
//  row's "liked N ago" — is injected per-row via the `detailLine` slot, since
//  that is the part rows should render differently.
//
//  The widget rows lead with the artist (bold, larger) rather than the song
//  title, use widget-appropriate fonts/line limits instead of the
//  flowsheet/Liked defaults, sit at SwiftUI's default stack spacing rather than
//  the flowsheet's tighter 4pt, and have no third line — `leadingField`,
//  `leadingFont`/`trailingFont`, `leadingLineLimit`/`trailingLineLimit`, and
//  `spacing` cover that without changing the two existing callers, which don't
//  pass them and keep passing their own `detailLine` (issue #771).
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

/// The leading text column of a song row: a bold "leading" line over a plain
/// "trailing" line over a caller-supplied detail line. Typography matches the
/// flowsheet by default so the Liked tab presents a song the same way the
/// playlist does.
struct SongInfoColumn<Song: SongDisplayable, Detail: View>: View {
    /// Which field renders first (bold) vs. second (plain). The flowsheet and
    /// Liked rows lead with the song title (the default); the widget's compact
    /// rows lead with the artist instead.
    enum LeadingField {
        case songTitle
        case artistName
    }

    let song: Song
    var leadingField: LeadingField = .songTitle
    var leadingFont: Font? = nil
    var trailingFont: Font? = nil
    // Line limits match the flowsheet/Liked row's fixed 2.5 aspect: the
    // leading line over two lines, the trailing line over one, so a long
    // title truncates rather than overflowing the fixed height.
    var leadingLineLimit: Int = 2
    var trailingLineLimit: Int = 1
    /// Vertical spacing between the lines. `4` is the flowsheet/Liked row's
    /// tighter-than-default value; the widget rows pass `nil` because their
    /// text used to sit directly in the layout's own `VStack` at SwiftUI's
    /// default spacing, and nesting it here at 4pt would silently retighten
    /// every widget family.
    var spacing: CGFloat? = 4
    @ViewBuilder var detailLine: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            line(Text(leadingText).fontWeight(.bold), font: leadingFont, lineLimit: leadingLineLimit)
            line(Text(trailingText), font: trailingFont, lineLimit: trailingLineLimit)
            detailLine()
        }
    }

    /// Applies the shared row typography to one line.
    ///
    /// `font` is applied only when non-`nil`. `View.font(_:)` writes its
    /// argument straight into `EnvironmentValues.font`, so `.font(nil)` doesn't
    /// mean "leave it alone" — it *overrides* an ancestor's font with "unset",
    /// which `Text` then resolves to `.body`. The flowsheet and Liked callers
    /// pass no font and applied no `.font` modifier before this column existed,
    /// so they have to keep inheriting.
    @ViewBuilder
    private func line(_ text: Text, font: Font?, lineLimit: Int) -> some View {
        let styled = text
            .foregroundStyle(.white)
            .lineLimit(lineLimit)
        if let font {
            styled.font(font)
        } else {
            styled
        }
    }

    private var leadingText: String {
        switch leadingField {
        case .songTitle: song.songTitle
        case .artistName: song.artistName
        }
    }

    private var trailingText: String {
        switch leadingField {
        case .songTitle: song.artistName
        case .artistName: song.songTitle
        }
    }
}
