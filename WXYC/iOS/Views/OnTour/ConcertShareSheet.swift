//
//  ConcertShareSheet.swift
//  WXYC
//
//  Presents the system share sheet for a concert's canonical
//  `https://wxyc.org/shows/<id>` link. The shared payload is the **bare URL and
//  nothing else** — never a URL concatenated into a sentence — because iMessage
//  only swaps in the App Clip / Open Graph card when the message body is a lone
//  shareable URL; a text-prefixed body permanently pins the recipient to the plain
//  link preview. Prose (title + poster thumbnail) rides in the sheet header via
//  `LPLinkMetadata`, the UIKit counterpart of SwiftUI's `SharePreview`. Do not fold
//  the title into the activity item — keep it in the metadata.
//
//  Why `UIActivityViewController` rather than `ShareLink`: the row affordance is a
//  `.contextMenu` item, and SwiftUI renders context-menu rows as native `UIMenu`
//  elements that strip attached gestures, so a context-menu `ShareLink` cannot
//  record `ConcertShareInitiated(surface: "row")`. Driving one representable from
//  parent state lets both surfaces — the detail chrome button and the row menu —
//  capture analytics on the same tap that opens the sheet, with an identical
//  bare-URL payload (so the App Clip card behaves the same from either surface).
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import LinkPresentation
import SwiftUI
import UIKit

/// A `UIViewControllerRepresentable` that shows the system share sheet for a
/// ``Concert``, sharing only its ``Concert/shareURL``.
struct ConcertShareSheet: UIViewControllerRepresentable {
    let concert: Concert

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let source = ConcertActivityItemSource(
            shareURL: concert.shareURL,
            title: BoxOfficeTicketPresenter(concert).shareTitle,
            thumbnail: Self.posterThumbnail(for: concert)
        )
        return UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    /// A square snapshot of the poster gradient, so the share-sheet header matches
    /// the poster art the recipient's card will carry. Rendered synchronously on
    /// the main actor via SwiftUI's `ImageRenderer`. Artwork-when-present is
    /// deferred: `image_url` is rare today, and the recipient's card pulls the real
    /// image from the share page regardless.
    @MainActor
    private static func posterThumbnail(for concert: Concert) -> UIImage? {
        let pair = PosterGradient.pair(for: concert)
        let gradient = LinearGradient(
            colors: [Color(pair.start), Color(pair.end)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: 240, height: 240)
        let renderer = ImageRenderer(content: gradient)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Supplies the share sheet's payload and rich header. The item returned for every
/// activity type is the lone `shareURL`; the title and thumbnail travel separately
/// in ``activityViewControllerLinkMetadata(_:)`` so the message body stays a bare
/// URL (see the file header for why that invariant is load-bearing).
///
/// Not `private`: `ConcertActivityItemSourceTests` reaches it via `@testable
/// import WXYC` to guard the bare-URL payload invariant.
final class ConcertActivityItemSource: NSObject, UIActivityItemSource {
    private let shareURL: URL
    private let title: String
    private let thumbnail: UIImage?

    init(shareURL: URL, title: String, thumbnail: UIImage?) {
        self.shareURL = shareURL
        self.title = title
        self.thumbnail = thumbnail
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        shareURL
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        // The payload is the bare URL and nothing else — see the file header.
        shareURL
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = shareURL
        metadata.url = shareURL
        if let thumbnail {
            metadata.imageProvider = NSItemProvider(object: thumbnail)
        }
        return metadata
    }
}

extension View {
    /// Presents the concert share sheet whenever `concert` becomes non-nil, and
    /// clears the binding on dismissal. Both On Tour share affordances — the detail
    /// chrome button and the row context menu — drive it through this modifier so
    /// they share one presentation path and one bare-URL payload.
    func concertShareSheet(concert: Binding<Concert?>) -> some View {
        sheet(item: concert) { ConcertShareSheet(concert: $0) }
    }
}
