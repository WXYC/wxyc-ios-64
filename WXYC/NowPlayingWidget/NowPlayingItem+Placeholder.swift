//
//  NowPlayingItem+Placeholder.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import Core
import AppServices
import Playlist

extension NowPlayingItem {
    static var placeholder: NowPlayingItem {
        NowPlayingItem(playcut: playcutsIterator.next()!)
    }
    
    private static var playcutsIterator = CircularIterator(placeholderPlaycuts)
    
    private static let placeholderPlaycuts: [Playcut] = [
        Playcut(
            id: 0,
            hour: 0,
            chronOrderID: 0,
            songTitle: "VI Scose Poise",
            labelName: nil,
            artistName: "Autechre",
            releaseTitle: "Confield"
        ),
        Playcut(
            id: 1,
            hour: 0,
            chronOrderID: 1,
            songTitle: "Belleville",
            labelName: nil,
            artistName: "Laurel Halo",
            releaseTitle: "Atlas"
        ),
        Playcut(
            id: 2,
            hour: 0,
            chronOrderID: 2,
            songTitle: "Bismillahi 'Rrahmani 'Rrahim",
            labelName: nil,
            artistName: "Harold Budd",
            releaseTitle: "Pavilion of Dreams"
        ),
        Playcut(
            id: 3,
            hour: 0,
            chronOrderID: 3,
            songTitle: "Guinnevere",
            labelName: nil,
            artistName: "Miles Davis",
            releaseTitle: "Bitches Brew"
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

