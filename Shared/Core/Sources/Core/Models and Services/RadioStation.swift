//
//  RadioStation.swift
//  Core
//
//  Data model for radio station configuration (name, stream URL, etc.).
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

public struct RadioStation: Sendable {
    public let name: String
    public let description: String
    public let requestLine: URL
    public let streamURL: URL
    public let merchURL: URL
}

public extension RadioStation {
    static let WXYC = RadioStation(
        name: "WXYC",
        description: "WXYC 89.3 FM is the non-commercial student-run radio station of the University of North Carolina at Chapel Hill. We broadcast at 1100 watts from the student union on the UNC campus, 24 hours a day, 365 days a year. Our coverage area encompasses approximately 900 square miles in and around Chapel Hill, Durham, Pittsboro, Apex, and parts of Raleigh.",
        requestLine: URL(string: "tel://9199628989")!,
        streamURL: URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!,
        merchURL: URL(string: "https://merch.wxyc.org")!
    )
}
