//
//  NowPlayingHeadline.swift
//  Playlist
//
//  What a surface names while a specialty show is on the air with no song of its own yet:
//  the program over the person, with the program's tagline.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// The program over the person, in the order the Lock Screen uses: the program takes the bold line.
public struct NowPlayingHeadline: Sendable, Equatable {
    public let program: SpecialtyShowRef
    /// The DJ handle. The who's-on name and the guest lines are a later addition.
    public let person: String

    public init(program: SpecialtyShowRef, person: String) {
        self.program = program
        self.person = person
    }

    /// The program's tagline, shown in the label's place until the first song or who's-on entry.
    public var tagline: String? { program.tagline }
}

public extension NowPlayingLead {
    /// The headline this lead calls for, naming `person` under the program, or `nil` when the lead
    /// names something else: a song, a who's-on entry, a freeform DJ, or nothing. Exhaustive, so a new
    /// lead has to decide whether it headlines.
    func headline(person: String) -> NowPlayingHeadline? {
        switch self {
        case .specialtyCard(let program): NowPlayingHeadline(program: program, person: person)
        case .song, .spotlight, .djHandle, .nothing: nil
        }
    }
}
