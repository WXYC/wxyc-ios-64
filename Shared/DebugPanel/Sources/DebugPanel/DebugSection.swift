//
//  DebugSection.swift
//  DebugPanel
//
//  Grouped-card container that stands in for a `Form` `Section`, laying out a
//  header, card-backed content, and footer in plain stacks so the debug panel
//  doesn't inherit the row press-highlight of a `List`/`Form`.
//
//  Created by Jake Bromberg on 06/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if DEBUG
/// A visual stand-in for a `Form` `Section`.
///
/// Lays its content out in a `VStack` inside a rounded card, with optional
/// uppercased header and secondary footer text, mirroring the grouped look of a
/// `Form` section without the `List` row selection highlighting that appears
/// whenever a row is tapped.
struct DebugSection<Content: View>: View {
    private let header: String?
    private let footer: String?
    private let content: Content

    init(
        header: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.footnote)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.primary.opacity(0.1), in: .rect(cornerRadius: 16))

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
}
#endif
