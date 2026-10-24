//
//  PlaylistShow.swift
//  Playlist
//
//  One airing from the flowsheet response's top-level `shows` array, and the
//  per-show header the scrollback draws from it.
//
//  Created by Jake Bromberg on 10/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A show that overlaps the fetched window (`shows[]`), keyed on ``Playlist/shows`` by `id`,
/// which matches the `show_id` of the rows that belong to it.
///
/// Hand-written `Codable` for the same reason as ``SpecialtyShowRef``: a malformed optional field
/// degrades to `nil` rather than costing the show. `specialty` is present only when a DJ signed on
/// as the program; the app never infers one from the time slot.
public struct PlaylistShow: Codable, Sendable, Hashable {
    public let id: UInt64
    /// The airing's own name, shown as a subtitle under the program name.
    public let showName: String?
    public let djName: String?
    public let specialty: SpecialtyShowRef?

    public init(id: UInt64, showName: String?, djName: String?, specialty: SpecialtyShowRef?) {
        self.id = id
        self.showName = showName
        self.djName = djName
        self.specialty = specialty
    }

    private enum CodingKeys: String, CodingKey {
        case id, specialty
        case showName = "show_name"
        case djName = "dj_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decode(Int.self, forKey: .id)
        guard let id = UInt64(exactly: rawID) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "negative show id")
        }
        self.id = id
        showName = (try? container.decodeIfPresent(String.self, forKey: .showName)) ?? nil
        djName = (try? container.decodeIfPresent(String.self, forKey: .djName)) ?? nil
        specialty = (try? container.decodeIfPresent(SpecialtyShowRef.self, forKey: .specialty)) ?? nil
    }
}

/// The header drawn above a specialty show's rows in the scrollback. Freeform shows have none.
public struct ShowHeader: Sendable, Equatable {
    public let program: SpecialtyShowRef
    public let showName: String?
    public let djHandle: String?

    public init(program: SpecialtyShowRef, showName: String?, djHandle: String?) {
        self.program = program
        self.showName = showName
        self.djHandle = djHandle
    }
}

public extension Playlist {
    /// The specialty headers for `items`, keyed by the id of the newest row of each show's run
    /// (items are newest first, so the header sits above the run). A row with no `show_id` joins
    /// whatever run it sits in; a row whose show is missing from ``shows`` or has no specialty
    /// opens no header. The open show's run gets none while the ``specialtyCard`` already represents
    /// that show, so each show is introduced once; past shows keep theirs.
    func showHeaders(of items: [TimelineItem]) -> [UInt64: ShowHeader] {
        var headers: [UInt64: ShowHeader] = [:]
        var currentShowID: UInt64?
        let cardShowID: UInt64? = if specialtyCard != nil, case .dj(_, let show?) = onAir { show.id } else { nil }
        for item in items {
            let showID = switch item {
            case .playcut(let playcut): playcut.showID
            case .spotlight(let entry): entry.showID
            case .seam, .showMarker: UInt64?.none
            }
            guard let showID, showID != currentShowID else { continue }
            currentShowID = showID
            if showID == cardShowID { continue }
            if let show = shows[showID], let program = show.specialty {
                headers[item.id] = ShowHeader(program: program, showName: show.showName, djHandle: show.djName)
            }
        }
        return headers
    }
}
