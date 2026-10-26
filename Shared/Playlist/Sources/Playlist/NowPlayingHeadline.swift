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
    /// The open show's current who's-on entry's name when it has one, otherwise the DJ handle.
    public let person: String

    /// Whether the tagline shows; see ``Playlist/showsProgramTagline``.
    public let showsTagline: Bool

    public init(program: SpecialtyShowRef, person: String, showsTagline: Bool = true) {
        self.program = program
        self.person = person
        self.showsTagline = showsTagline
    }

    /// The program's tagline, shown in the label's place until the first song or who's-on entry, and `nil` after.
    public var tagline: String? { showsTagline ? program.tagline : nil }
}

public extension Playlist {
    /// The specialty program on the air over the DJ handle, or `nil` for a freeform show, automation,
    /// or unknown on-air. Non-nil whatever leads: the one derivation of the program and its person
    /// line (the who's-on name, else the DJ handle), read by ``nowPlayingSpotlight`` and the widget.
    var programHeadline: NowPlayingHeadline? {
        guard case .dj(let handle, let show?) = onAir, let program = show.specialty else { return nil }
        return NowPlayingHeadline(program: program, person: openShowSpotlight?.name ?? handle, showsTagline: showsProgramTagline)
    }
}
