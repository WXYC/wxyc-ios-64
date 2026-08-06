//
//  DetailCard.swift
//  WXUI
//
//  The `.primary.opacity(0.1)`-filled, radius-16 card behind the flowsheet's
//  Playcut Detail sections — one shared container instead of six copies of
//  `.padding().background(RoundedRectangle(cornerRadius: 16).fill(.primary
//  .opacity(0.1)))`, each pairing it with the same `.detailSectionHeader`
//  title line. `SongRowPanel` (in the app target) is the sibling abstraction
//  for the flowsheet's row chrome; this is the section-card counterpart.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A rounded, tinted card for one Playcut Detail section, with an optional
/// `.detailSectionHeader`-styled title above the content.
///
/// Pass `padded: false` for content that manages its own sizing (a fixed-
/// height loading placeholder, say) and would look wrong with the card's
/// standard interior padding added on top.
public struct DetailCard<Content: View>: View {
    /// The card's corner radius. Canon: 16pt.
    public static var cornerRadius: CGFloat { 16 }
    /// The card's fill opacity, over `.primary`. Canon: 0.1.
    public static var fillOpacity: Double { 0.1 }

    let title: String?
    let padded: Bool
    @ViewBuilder let content: () -> Content

    /// - Parameters:
    ///   - title: When non-`nil`, rendered above the content in
    ///     `.detailSectionHeader` style. Omit for a card with no header line.
    ///   - padded: Whether the card applies its own standard interior
    ///     padding. Default `true`; pass `false` when the content already
    ///     controls its own size (see the type's discussion).
    ///   - content: The card's body.
    public init(
        title: String? = nil,
        padded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.padded = padded
        self.content = content
    }

    public var body: some View {
        Group {
            if padded {
                stack.padding()
            } else {
                stack
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(.primary.opacity(Self.fillOpacity))
        )
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 12) {
            if Self.showsHeader(title: title) {
                Text(title ?? "")
                    .font(.detailSectionHeader)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content()
        }
    }

    /// Whether the header line renders for a given `title`. Exposed as a pure
    /// function (rather than inlined in `body`) so the visibility rule is
    /// directly testable.
    static func showsHeader(title: String?) -> Bool {
        title != nil
    }
}
