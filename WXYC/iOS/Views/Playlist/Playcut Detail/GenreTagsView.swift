//
//  GenreTagsView.swift
//  WXYC
//
//  Horizontal scrolling genre and style tags for the playcut detail view.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

struct GenreTagsView: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: .capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    GenreTagsView(tags: ["Electronic", "IDM", "Abstract", "Experimental"])
        .padding()
        .background(.black)
}
