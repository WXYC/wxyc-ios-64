//
//  DJEntityIntentPersonBridgeTests.swift
//  WXYCIntents
//
//  Field-mapping coverage for CC-C1 — the `DJEntity` -> `IntentPerson` bridge
//  and its inverse. Pins what each field the ticket specifies actually maps
//  to (`.applicationDefined(dj.id)`, `.displayName(dj.name)`, `handle: nil`)
//  and what importing does with a person shape the bridge never exports. The
//  `Transferable`/`IntentValueRepresentation` wiring in `DJEntity.swift` needs
//  Swift 6.4 (`IntentValueRepresentation` isn't present in the stable SDK at
//  all, despite its own `@available(iOS 26.4, *)` annotation — see that
//  file's header) so it isn't exercised here; these tests cover the pure
//  `intentPerson`/`from(intentPerson:)` conversion the gated conformance
//  delegates to.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents
import Foundation
import Testing
@testable import WXYCIntents

@Suite("DJEntity ↔ IntentPerson bridge (CC-C1)")
struct DJEntityIntentPersonBridgeTests {
    @Test("exporting maps identifier, name, and a nil handle")
    func exportingMapsFields() {
        let dj = DJEntity(djName: "Jake B")

        let person = dj.intentPerson

        #expect(person.identifier == .applicationDefined(dj.id.entityIdentifierString))
        #expect(person.name == .displayName("jake b"))
        #expect(person.handle == nil)
    }

    @Test("exporting dedup name variants produces the same identifier")
    func exportingDedupVariantsShareIdentifier() {
        let canonical = DJEntity(djName: "Jake B")
        let variant = DJEntity(djName: "  jake   b  ")

        #expect(canonical.intentPerson.identifier == variant.intentPerson.identifier)
        #expect(canonical.intentPerson.name == variant.intentPerson.name)
    }

    @Test("importing a displayName round-trips to the exporting entity's id and name")
    func importingRoundTripsDisplayName() throws {
        let original = DJEntity(djName: "DJ Rembert")

        let imported = try DJEntity.from(intentPerson: original.intentPerson)

        #expect(imported.id == original.id)
        #expect(imported.normalizedName == original.normalizedName)
    }

    @Test("importing a person with structured name components throws rather than fabricating a DJ")
    func importingComponentsNameThrows() {
        let components = PersonNameComponents()
        let person = IntentPerson(
            identifier: .applicationDefined("42"),
            name: .components(components),
            handle: nil
        )

        #expect(throws: DJEntity.IntentPersonImportError.unsupportedName(.components(components))) {
            try DJEntity.from(intentPerson: person)
        }
    }

    @Test("importing a person with an unknown name throws")
    func importingUnknownNameThrows() {
        let person = IntentPerson(identifier: .unknown, name: .unknown, handle: nil)

        #expect(throws: DJEntity.IntentPersonImportError.unsupportedName(.unknown)) {
            try DJEntity.from(intentPerson: person)
        }
    }
}
