//
//  SpecialtyShowClientTests.swift
//  Playlist
//
//  Verifies the `GET /specialty-shows` model decode and the client's cache: served from memory
//  inside the 5-minute window, revalidated with `If-None-Match` after it, replaced on a 200.
//  The network is a stub; nothing here reaches production.
//
//  Created by Jake Bromberg on 10/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import os
@testable import Playlist

private let catalogBody = Data("""
[
  {"id": 3, "slug": "hogwash", "name": "Hogwash", "short_name": "Hogwash", "tagline": "Weird and wonderful",
   "logs_playcuts": true, "description": null, "active": true, "default_request_mode": null,
   "slots": [{"day": 2, "start_time": "21:00", "duration_minutes": 120, "cadence": "weekly"}]},
  {"id": 4, "slug": "rock-lobster", "name": "Rock Lobster", "short_name": "Lobster", "logs_playcuts": false, "active": true,
   "slots": [{"day": 6, "start_time": "08:30", "duration_minutes": 60, "cadence": "last_of_month"},
             {"day": 0, "start_time": "10:00", "duration_minutes": 30, "cadence": "a_future_cadence"}]}
]
""".utf8)

/// Replies from a queue of canned responses and records every request it sees.
private final class StubSpecialtyProtocol: URLProtocol, @unchecked Sendable {
    struct Reply { let status: Int; let etag: String?; let body: Data }
    private struct State { var replies: [Reply] = []; var requests: [URLRequest] = [] }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func reset(_ replies: [Reply]) { state.withLock { $0 = State(replies: replies) } }
    static var requests: [URLRequest] { state.withLock { $0.requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let reply = Self.state.withLock { state -> Reply in
            state.requests.append(request)
            return state.replies.isEmpty ? Reply(status: 500, etag: nil, body: Data()) : state.replies.removeFirst()
        }
        var headers = ["Cache-Control": "public, max-age=300"]
        headers["ETag"] = reply.etag
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000_000))
    var now: Date { lock.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { lock.withLock { $0.addTimeInterval(seconds) } }
}

private func makeClient(clock: Clock) -> SpecialtyShowClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubSpecialtyProtocol.self]
    return SpecialtyShowClient(
        baseURL: URL(string: "https://example.invalid")!,
        session: URLSession(configuration: configuration),
        now: { clock.now }
    )
}

@Suite("Specialty Show Client Tests", .serialized)
struct SpecialtyShowClientTests {
    @Test("Decodes slug, name, and slots, keeping an unknown cadence as a plain string")
    func decodesCatalog() throws {
        let shows = try JSONDecoder().decode([SpecialtyShow].self, from: catalogBody)

        #expect(shows.map(\.slug) == ["hogwash", "rock-lobster"])
        #expect(shows[0].name == "Hogwash")
        #expect(shows[0].slots == [SpecialtyShow.Slot(day: 2, startTime: "21:00", durationMinutes: 120, cadence: "weekly")])
        #expect(shows[1].slots.map(\.cadence) == ["last_of_month", "a_future_cadence"])
    }

    @Test("Requests GET /specialty-shows with no conditional header the first time")
    func firstRequestIsUnconditional() async throws {
        StubSpecialtyProtocol.reset([.init(status: 200, etag: "\"v1\"", body: catalogBody)])

        let shows = try await makeClient(clock: Clock()).shows()

        #expect(shows.count == 2)
        let request = try #require(StubSpecialtyProtocol.requests.first)
        #expect(request.url?.path == "/specialty-shows")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    #if DEBUG
    @Test("programs() returns the catalog as full refs from the one cached request")
    func programsShareTheCache() async throws {
        StubSpecialtyProtocol.reset([.init(status: 200, etag: "\"v1\"", body: catalogBody)])
        let client = makeClient(clock: Clock())

        _ = try await client.shows()
        let programs = try await client.programs()

        #expect(programs.map(\.slug) == ["hogwash", "rock-lobster"])
        #expect(programs[0].tagline == "Weird and wonderful")
        #expect(programs[1].logsPlaycuts == false)
        #expect(StubSpecialtyProtocol.requests.count == 1)
    }
    #endif

    @Test("Serves from memory inside the 5-minute window without a request")
    func servesWithinWindow() async throws {
        StubSpecialtyProtocol.reset([.init(status: 200, etag: "\"v1\"", body: catalogBody)])
        let clock = Clock()
        let client = makeClient(clock: clock)

        _ = try await client.shows()
        clock.advance(299)
        let shows = try await client.shows()

        #expect(shows.count == 2)
        #expect(StubSpecialtyProtocol.requests.count == 1)
    }

    @Test("Revalidates with If-None-Match at the window's edge and keeps the cached catalog on a 304")
    func revalidatesWithETag() async throws {
        StubSpecialtyProtocol.reset([
            .init(status: 200, etag: "\"v1\"", body: catalogBody),
            .init(status: 304, etag: "\"v1\"", body: Data()),
        ])
        let clock = Clock()
        let client = makeClient(clock: clock)

        _ = try await client.shows()
        clock.advance(300)
        let shows = try await client.shows()

        #expect(shows.count == 2)
        #expect(StubSpecialtyProtocol.requests.count == 2)
        #expect(StubSpecialtyProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    }

    @Test("A 304 restarts the window")
    func notModifiedRestartsWindow() async throws {
        StubSpecialtyProtocol.reset([
            .init(status: 200, etag: "\"v1\"", body: catalogBody),
            .init(status: 304, etag: nil, body: Data()),
        ])
        let clock = Clock()
        let client = makeClient(clock: clock)

        _ = try await client.shows()
        clock.advance(300)
        _ = try await client.shows()
        clock.advance(299)
        _ = try await client.shows()

        #expect(StubSpecialtyProtocol.requests.count == 2)
    }

    @Test("A 200 after the window replaces the catalog and the ETag")
    func changedCatalogReplacesCache() async throws {
        let renamed = Data(#"[{"id": 3, "slug": "hogwash", "name": "Hogwash II", "short_name": "H", "logs_playcuts": true, "active": true, "slots": []}]"#.utf8)
        StubSpecialtyProtocol.reset([
            .init(status: 200, etag: "\"v1\"", body: catalogBody),
            .init(status: 200, etag: "\"v2\"", body: renamed),
            .init(status: 304, etag: "\"v2\"", body: Data()),
        ])
        let clock = Clock()
        let client = makeClient(clock: clock)

        _ = try await client.shows()
        clock.advance(300)
        #expect(try await client.shows().map(\.name) == ["Hogwash II"])
        clock.advance(300)
        _ = try await client.shows()

        #expect(StubSpecialtyProtocol.requests[2].value(forHTTPHeaderField: "If-None-Match") == "\"v2\"")
    }

    @Test("A server error throws and does not poison the cache")
    func serverErrorThrows() async throws {
        StubSpecialtyProtocol.reset([
            .init(status: 500, etag: nil, body: Data()),
            .init(status: 200, etag: "\"v1\"", body: catalogBody),
        ])
        let client = makeClient(clock: Clock())

        await #expect(throws: (any Error).self) { try await client.shows() }
        #expect(try await client.shows().count == 2)
    }

    @Test("A second client is not served another client's cache")
    func cacheIsPerClient() async throws {
        StubSpecialtyProtocol.reset([
            .init(status: 200, etag: "\"v1\"", body: catalogBody),
            .init(status: 200, etag: "\"v1\"", body: catalogBody),
        ])
        _ = try await makeClient(clock: Clock()).shows()
        _ = try await makeClient(clock: Clock()).shows()

        #expect(StubSpecialtyProtocol.requests.count == 2)
    }
}
