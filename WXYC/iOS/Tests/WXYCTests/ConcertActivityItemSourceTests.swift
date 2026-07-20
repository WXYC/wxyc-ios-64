//
//  ConcertActivityItemSourceTests.swift
//  WXYC
//
//  Guards the load-bearing invariant behind On Tour sharing: the share payload is
//  the bare `wxyc.org/shows/<id>` URL and nothing else, with the title/thumbnail
//  riding only in the link metadata. iMessage swaps in the App Clip / Open Graph
//  card only when the message body is a lone shareable URL, so a regression that
//  folds prose into the activity item would silently disable the rich card. This
//  suite fails the moment that happens.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import LinkPresentation
import Testing
import UIKit
@testable import WXYC

@Suite("ConcertActivityItemSource")
struct ConcertActivityItemSourceTests {
    private let url = URL(string: "https://wxyc.org/shows/4821")!
    private let title = "Jessica Pratt at Cat's Cradle"

    private func makeSource() -> ConcertActivityItemSource {
        ConcertActivityItemSource(shareURL: url, title: title, thumbnail: nil)
    }

    private func makeController() -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    @Test("The shared item is the bare URL — no prose folded in")
    func itemIsBareURL() {
        let item = makeSource().activityViewController(makeController(), itemForActivityType: nil)
        #expect(item as? URL == url)
        // The title must never ride in the payload; only a bare URL lets iMessage
        // swap in the App Clip / Open Graph card.
        #expect((item as? String)?.contains(title) != true)
    }

    @Test("The placeholder item is the bare URL")
    func placeholderIsBareURL() {
        #expect(makeSource().activityViewControllerPlaceholderItem(makeController()) as? URL == url)
    }

    @Test("Prose rides in the link metadata, not the payload")
    func metadataCarriesTitle() {
        let metadata = makeSource().activityViewControllerLinkMetadata(makeController())
        #expect(metadata?.title == title)
        #expect(metadata?.originalURL == url)
    }
}
