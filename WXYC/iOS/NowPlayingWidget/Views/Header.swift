//
//  Header.swift
//  WXYC
//
//  Header component for widget layouts.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

struct Header: View {
    var entry: NowPlayingTimelineEntry

    var body: some View {
        HStack(alignment: .center) {
            if let artwork = entry.artwork {
                artwork
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(10)
                    .frame(width: 100, height: 100)
            } else {
                Image.logo
                    .frame(width: 100, height: 100, alignment: .leading)
            }

            VStack(alignment: .leading) {
                SongInfoColumn(
                    song: entry,
                    leadingField: .artistName,
                    leadingFont: .headline,
                    trailingFont: .subheadline,
                    leadingLineLimit: 1,
                    trailingLineLimit: 1,
                    spacing: nil
                ) { EmptyView() }

                PlayButton()
                    .frame(alignment: .bottom)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
