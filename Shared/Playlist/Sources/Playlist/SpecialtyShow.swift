//
//  SpecialtyShow.swift
//  Playlist
//
//  One program in the specialty-show catalog served by `GET /specialty-shows`.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A specialty program from the public catalog (`GET /specialty-shows`): active programs only.
///
/// `slug` is the stable identifier and is never reused, even by a retired program. Hand-written
/// `Codable`, like ``SpecialtyShowRef``, so an unknown `cadence` string survives the decode.
public struct SpecialtyShow: Codable, Sendable, Hashable {
    /// One recurring broadcast slot, on the station's America/New_York wall clock.
    public struct Slot: Codable, Sendable, Hashable {
        /// 0 = Monday, matching the schedule's `day`.
        public let day: Int
        /// `HH:MM`.
        public let startTime: String
        public let durationMinutes: Int
        /// The raw `cadence` string (`weekly`, `some_weeks`, `last_of_month`); not an enum so a new value survives.
        public let cadence: String

        public init(day: Int, startTime: String, durationMinutes: Int, cadence: String) {
            self.day = day
            self.startTime = startTime
            self.durationMinutes = durationMinutes
            self.cadence = cadence
        }

        private enum CodingKeys: String, CodingKey {
            case day, cadence
            case startTime = "start_time"
            case durationMinutes = "duration_minutes"
        }
    }

    public let id: Int
    public let slug: String
    public let name: String
    public let slots: [Slot]

    public init(id: Int, slug: String, name: String, slots: [Slot] = []) {
        self.id = id
        self.slug = slug
        self.name = name
        self.slots = slots
    }
}
