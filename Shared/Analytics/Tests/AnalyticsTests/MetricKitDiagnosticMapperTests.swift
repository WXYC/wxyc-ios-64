//
//  MetricKitDiagnosticMapperTests.swift
//  Analytics
//
//  Verifies MetricKit hang and crash diagnostic JSON maps to a PostHog
//  `$exception` event carrying `source = metrickit` and the call-stack frames.
//
//  Created by Jake Bromberg on 10/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("MetricKitDiagnosticMapper")
struct MetricKitDiagnosticMapperTests {
    /// Two threads; the attributed one has a branching tree whose heavier branch must win.
    static let hangJSON = """
    {
      "callStackTree": {
        "callStackPerThread": true,
        "callStacks": [
          {
            "threadAttributed": false,
            "callStackRootFrames": [
              {"binaryUUID": "OTHER", "offsetIntoBinaryTextSegment": 1, "sampleCount": 1,
               "binaryName": "libsystem_kernel.dylib", "address": 100}
            ]
          },
          {
            "threadAttributed": true,
            "callStackRootFrames": [
              {"binaryUUID": "AAAA", "offsetIntoBinaryTextSegment": 4096, "sampleCount": 10,
               "binaryName": "WXYC", "address": 4300000000,
               "subFrames": [
                 {"binaryUUID": "BBBB", "offsetIntoBinaryTextSegment": 8, "sampleCount": 2,
                  "binaryName": "UIKitCore", "address": 5000},
                 {"binaryUUID": "CCCC", "offsetIntoBinaryTextSegment": 16, "sampleCount": 8,
                  "binaryName": "Foundation", "address": 6000}
               ]}
            ]
          }
        ]
      },
      "diagnosticMetaData": {"appVersion": "3.2.1"}
    }
    """

    @Test("Hang maps to a metrickit $exception with the attributed thread's heaviest path")
    func mapsHang() throws {
        let event = try #require(MetricKitDiagnosticMapper.event(kind: .hang, json: Data(Self.hangJSON.utf8)))

        #expect(type(of: event).name == "$exception")
        let props = try #require(event.properties)
        #expect(props["source"] as? String == "metrickit")
        #expect(props["diagnostic_kind"] as? String == "hang")

        let list = try #require(props["$exception_list"] as? [[String: Any]])
        let exception = try #require(list.first)
        #expect(exception["type"] as? String == "AppHang")
        let stacktrace = try #require(exception["stacktrace"] as? [String: Any])
        let frames = try #require(stacktrace["frames"] as? [[String: Any]])
        #expect(frames.compactMap { $0["module"] as? String } == ["WXYC", "Foundation"])
        #expect(frames.first?["debug_id"] as? String == "AAAA")
        #expect(frames.first?["image_offset"] as? Int == 4096)
        #expect(frames.first?["instruction_addr"] as? String == "0x1004ccb00")
    }

    @Test("Crash carries kind=crash and the termination details")
    func mapsCrash() throws {
        let json = """
        {"callStackTree": {"callStacks": [{"threadAttributed": true, "callStackRootFrames": [
           {"binaryUUID": "AAAA", "offsetIntoBinaryTextSegment": 1, "sampleCount": 1, "binaryName": "WXYC", "address": 16}]}]},
         "diagnosticMetaData": {"signal": 11, "exceptionType": 1, "terminationReason": "Namespace SIGNAL"}}
        """

        let event = try #require(MetricKitDiagnosticMapper.event(kind: .crash, json: Data(json.utf8)))

        let props = try #require(event.properties)
        #expect(props["diagnostic_kind"] as? String == "crash")
        let exception = try #require((props["$exception_list"] as? [[String: Any]])?.first)
        #expect(exception["type"] as? String == "Crash")
        #expect(exception["value"] as? String == "Namespace SIGNAL (signal 11)")
    }

    @Test("Malformed or stackless JSON produces no event", arguments: ["not json", "{}", #"{"callStackTree":{"callStacks":[]}}"#])
    func rejectsUnusableJSON(json: String) {
        #expect(MetricKitDiagnosticMapper.event(kind: .hang, json: Data(json.utf8)) == nil)
    }
}
