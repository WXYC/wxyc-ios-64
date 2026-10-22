//
//  RadioShowEntityTests.swift
//  WXYCIntents
//
//  Coverage for the iOS 27 `radioShow` catalog entity: a program maps to title = name and id = slug,
//  and its query resolves a slug from the catalog or from an already-decoded `on_air.specialty`.
//  The catalog is a stub closure; nothing here reaches the network.
//
//  Gated to Swift 6.4 / iOS 27 (the audio AppSchema).
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

#if compiler(>=6.4)
#if !os(watchOS) && !os(tvOS)
import Foundation
import Playlist
import Testing
@testable import WXYCIntents

@Suite("RadioShowEntity (iOS 27 audio schema)")
struct RadioShowEntityTests {
    private static let hogwash = SpecialtyShow(id: 3, slug: "hogwash", name: "Hogwash")
    private static let lobster = SpecialtyShow(id: 4, slug: "rock-lobster", name: "Rock Lobster")

    @available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
    private func query(catalog: [SpecialtyShow] = [hogwash, lobster]) -> RadioShowEntity.RadioShowEntityQuery {
        RadioShowEntity.RadioShowEntityQuery(catalog: { catalog })
    }

    @Test("A catalog program maps to an entity titled with its name and keyed by its slug")
    func mapsCatalogProgram() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let entity = RadioShowEntity(show: Self.hogwash)

        #expect(entity.id == "hogwash")
        #expect(entity.title == "Hogwash")
        #expect(String(localized: entity.displayRepresentation.title) == "Hogwash")
    }

    @Test("A decoded specialty maps the same way")
    func mapsDecodedSpecialty() {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let entity = RadioShowEntity(specialty: SpecialtyShowRef(id: 4, slug: "rock-lobster", name: "Rock Lobster"))

        #expect(entity.id == "rock-lobster")
        #expect(entity.title == "Rock Lobster")
    }

    @Test("Resolves slugs from the catalog in the caller's order, dropping unknown ones")
    func resolvesFromCatalog() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let entities = try await query().entities(for: ["rock-lobster", "no-such-show", "hogwash"])

        #expect(entities.map(\.id) == ["rock-lobster", "hogwash"])
    }

    @Test("Resolves from an already-decoded specialty without consulting the catalog")
    func resolvesFromDecodedSpecialty() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let specialty = SpecialtyShowRef(id: 9, slug: "new-show", name: "New Show")
        let throwing = RadioShowEntity.RadioShowEntityQuery(catalog: { throw URLError(.notConnectedToInternet) })

        let entity = try await throwing.entity(slug: "new-show", specialty: specialty)

        #expect(entity?.title == "New Show")
    }

    @Test("A specialty for a different slug falls back to the catalog")
    func mismatchedSpecialtyFallsBack() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let specialty = SpecialtyShowRef(id: 9, slug: "new-show", name: "New Show")

        let entity = try await query().entity(slug: "hogwash", specialty: specialty)

        #expect(entity?.title == "Hogwash")
    }

    @Test("An unknown slug resolves to nothing")
    func unknownSlug() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        #expect(try await query().entity(slug: "nope", specialty: nil) == nil)
    }

    @Test("A catalog failure propagates")
    func catalogFailure() async {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        let failing = RadioShowEntity.RadioShowEntityQuery(catalog: { throw URLError(.timedOut) })

        await #expect(throws: URLError.self) { try await failing.entities(for: ["hogwash"]) }
    }

    @Test("Suggestions are the whole catalog")
    func suggestions() async throws {
        guard #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) else { return }
        #expect(try await query().suggestedEntities().map(\.id) == ["hogwash", "rock-lobster"])
    }
}
#endif
#endif
