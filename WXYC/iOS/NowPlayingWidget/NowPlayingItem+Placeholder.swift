//
//  NowPlayingItem+Placeholder.swift
//  WXYC
//
//  Placeholder data for widget previews.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Foundation
import Playlist

extension NowPlayingItem {
    static var placeholder: NowPlayingItem {
        placeholderLock.lock()
        let playcut = playcutsIterator.next()!
        placeholderLock.unlock()
        return NowPlayingItem(playcut: playcut)
    }

    private static let placeholderLock = NSLock()
    private static var playcutsIterator = CircularIterator(placeholderPlaycuts)
    
    /// The widget-gallery placeholder rotation. Four entries, one per
    /// `NowPlayingItem.placeholder` evaluation in `Provider` — `placeholder(in:)`
    /// and the `context.isPreview` timeline branch each take exactly four, and
    /// `LargeNowPlayingWidgetEntryView`'s `ForEach` keys on `playcut.id`, so the
    /// count and the distinct ids are both load-bearing.
    ///
    /// Built through `Playcut.init` rather than `Playcut.stub()`: the widget
    /// extension target doesn't link `PlaylistTesting`. See `PreviewFixtures` for
    /// why. The four tracks are the WXYC-canonical fixture set from
    /// `docs/test-fixtures.md`.
    private static let placeholderPlaycuts: [Playcut] = [
        Playcut(
            id: 0,
            hour: 0,
            chronOrderID: 0,
            timeCreated: 0,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        ),
        Playcut(
            id: 1,
            hour: 0,
            chronOrderID: 1,
            timeCreated: 0,
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again"
        ),
        Playcut(
            id: 2,
            hour: 0,
            chronOrderID: 2,
            timeCreated: 0,
            songTitle: "Call Your Name",
            labelName: nil,
            artistName: "Chuquimamani-Condori",
            releaseTitle: "Edits"
        ),
        Playcut(
            id: 3,
            hour: 0,
            chronOrderID: 3,
            timeCreated: 0,
            songTitle: "In a Sentimental Mood",
            labelName: "Impulse Records",
            artistName: "Duke Ellington & John Coltrane",
            releaseTitle: "Duke Ellington & John Coltrane"
        )
    ]
        
    private struct CircularIterator<Element>: IteratorProtocol {
        let sequence: any Sequence<Element>
        private var iterator: any IteratorProtocol<Element>
        
        init(_ sequence: any Sequence<Element>) {
            self.sequence = sequence
            self.iterator = sequence.makeIterator()
        }
        
        mutating func next() -> Element? {
            if let next = iterator.next() {
                return next
            } else {
                iterator = sequence.makeIterator()
                return iterator.next()
            }
        }
    }
}
