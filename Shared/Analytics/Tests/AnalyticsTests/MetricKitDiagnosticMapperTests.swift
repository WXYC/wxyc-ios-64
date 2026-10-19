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

    @Test("Hang maps to a metrickit $exception with the attributed thread's heaviest path, oldest frame first")
    func mapsHang() throws {
        let event = try #require(MetricKitDiagnosticMapper.event(kind: .hang, json: Data(Self.hangJSON.utf8)))

        #expect(type(of: event).name == "$exception")
        let props = try #require(event.properties)
        #expect(props["source"] as? String == "metrickit")
        #expect(props["diagnostic_kind"] as? String == "hang")

        let exception = try Self.exception(props)
        #expect(exception["type"] as? String == "AppHang")
        let frames = try Self.frames(exception)
        #expect(frames.compactMap { $0["module"] as? String } == ["WXYC", "Foundation"])
    }

    /// PostHog's error-tracking processor reads a frame as Apple only when `platform` is `apple`;
    /// without it a frame carrying `module` is read as Python and the whole event is rejected.
    /// A hang the app recovers from is not a crash, so only crashes are fatal.
    @Test("Exception level is error for a hang and fatal for a crash", arguments: [
        (MetricKitDiagnosticMapper.Kind.hang, "error"),
        (MetricKitDiagnosticMapper.Kind.crash, "fatal"),
    ])
    func exceptionLevel(kind: MetricKitDiagnosticMapper.Kind, level: String) throws {
        let event = try #require(MetricKitDiagnosticMapper.event(kind: kind, json: Data(Self.hangJSON.utf8)))
        #expect(try #require(event.properties)["$exception_level"] as? String == level)
    }

    @Test("Every frame has the Apple frame shape PostHog accepts")
    func framesHaveAppleShape() throws {
        let event = try #require(
            MetricKitDiagnosticMapper.event(kind: .hang, json: Data(Self.hangJSON.utf8), appBinaryName: "WXYC")
        )
        let frames = try Self.frames(Self.exception(try #require(event.properties)))

        for frame in frames {
            #expect(frame["platform"] as? String == "apple")
            #expect(!frame.keys.contains("debug_id"))
            #expect(!frame.keys.contains("image_offset"))
        }
        let first = try #require(frames.first)
        // address 4_300_000_000 = 0x1004ccb00; minus the 4096-byte text offset = 0x1004cbb00,
        // page-aligned to 0x1004cb000.
        #expect(first["instruction_addr"] as? String == "0x00000001004ccb00")
        #expect(first["image_addr"] as? String == "0x00000001004cb000")
        #expect(first["image_uuid"] as? String == "AAAA")
        #expect(first["package"] as? String == "WXYC")
        #expect(first["in_app"] as? Bool == true)
        #expect(frames.last?["in_app"] as? Bool == false)
    }

    @Test("Debug images list each referenced binary once, keyed to the frames' image_addr")
    func debugImages() throws {
        let event = try #require(MetricKitDiagnosticMapper.event(kind: .hang, json: Data(Self.hangJSON.utf8)))
        let props = try #require(event.properties)

        let images = try #require(props["$debug_images"] as? [[String: Any]])
        #expect(images.compactMap { $0["debug_id"] as? String } == ["AAAA", "CCCC"])
        let first = try #require(images.first)
        #expect(first["type"] as? String == "macho")
        #expect(first["code_file"] as? String == "WXYC")
        #expect(first["image_addr"] as? String == "0x00000001004cb000")
    }

    @Test("Hang duration, app version and the payload period are properties, not part of the exception value")
    func hangMetadataProperties() throws {
        let json = Self.hangJSON.replacingOccurrences(
            of: #""appVersion": "3.2.1""#,
            with: #""appVersion": "3.2.1", "appBuildVersion": "412", "hangDuration": "4.2 sec""#
        )
        let period = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), duration: 86_400)

        let event = try #require(MetricKitDiagnosticMapper.event(kind: .hang, json: Data(json.utf8), period: period))
        let props = try #require(event.properties)

        #expect(try Self.exception(props)["value"] as? String == "App hang")
        #expect(props["hang_duration"] as? String == "4.2 sec")
        #expect(props["diagnostic_app_version"] as? String == "3.2.1")
        #expect(props["diagnostic_app_build"] as? String == "412")
        #expect(props["diagnostic_period_start"] as? String == "2027-01-15T08:00:00Z")
        #expect(props["diagnostic_period_end"] as? String == "2027-01-16T08:00:00Z")
    }

    /// A real MetricKit crash call stack starts at the crash site: the root frame is the crashing
    /// frame, and its sub-frames walk out to dyld's `start`. PostHog wants the crash site last.
    static let crashJSON = """
    {"callStackTree": {"callStackPerThread": true, "callStacks": [{"threadAttributed": true, "callStackRootFrames": [
       {"binaryUUID": "APP", "offsetIntoBinaryTextSegment": 20480, "sampleCount": 1, "binaryName": "WXYC", "address": 4362096640,
        "subFrames": [
          {"binaryUUID": "UIKIT", "offsetIntoBinaryTextSegment": 1048577, "sampleCount": 1, "binaryName": "UIKitCore", "address": 6443499521,
           "subFrames": [
             {"binaryUUID": "CF", "offsetIntoBinaryTextSegment": 524289, "sampleCount": 1, "binaryName": "CoreFoundation", "address": 6442975233,
              "subFrames": [
                {"binaryUUID": "DYLD", "offsetIntoBinaryTextSegment": 8193, "sampleCount": 1, "binaryName": "dyld", "address": 6442459137}
              ]}
           ]}
        ]}
    ]}]},
     "diagnosticMetaData": {"signal": 6, "terminationReason": "Namespace SIGNAL"}}
    """

    @Test("A crash stack is reversed so dyld start is first and the crash site is last")
    func crashStackEndsAtCrashSite() throws {
        let event = try #require(
            MetricKitDiagnosticMapper.event(kind: .crash, json: Data(Self.crashJSON.utf8), appBinaryName: "WXYC")
        )
        let frames = try Self.frames(Self.exception(try #require(event.properties)))

        #expect(frames.compactMap { $0["module"] as? String } == ["dyld", "CoreFoundation", "UIKitCore", "WXYC"])
        let last = try #require(frames.last)
        #expect(last["image_uuid"] as? String == "APP")
        #expect(last["in_app"] as? Bool == true)
    }

    @Test("A crash stack deeper than the cap keeps the frames nearest the crash site, crash site last")
    func capsFrames() throws {
        var node = #"{"binaryUUID": "START", "offsetIntoBinaryTextSegment": 0, "sampleCount": 1, "binaryName": "dyld", "address": 1}"#
        for index in (2...40).reversed() {
            node = #"{"binaryUUID": "U\#(index)", "offsetIntoBinaryTextSegment": 0, "sampleCount": 1, "binaryName": "WXYC", "address": \#(index), "subFrames": [\#(node)]}"#
        }
        node = #"{"binaryUUID": "CRASH", "offsetIntoBinaryTextSegment": 0, "sampleCount": 1, "binaryName": "WXYC", "address": 41, "subFrames": [\#(node)]}"#
        let json = #"{"callStackTree": {"callStacks": [{"threadAttributed": true, "callStackRootFrames": [\#(node)]}]}}"#

        let event = try #require(MetricKitDiagnosticMapper.event(kind: .crash, json: Data(json.utf8), maxFrames: 16))
        let frames = try Self.frames(Self.exception(try #require(event.properties)))

        #expect(frames.count == 16)
        #expect(frames.first?["image_uuid"] as? String == "U16")
        #expect(frames.last?["image_uuid"] as? String == "CRASH")
    }

    /// A leaf frame's address minus its text offset lands on the page-aligned image base; a caller
    /// frame's return address lands one byte past it. Both must match the binary's one debug image.
    @Test("Frames of one binary at image offset +0 and +1 share the debug image's page-aligned image_addr")
    func pageAlignsImageAddress() throws {
        let json = """
        {"callStackTree": {"callStacks": [{"threadAttributed": true, "callStackRootFrames": [
           {"binaryUUID": "APP", "offsetIntoBinaryTextSegment": 8192, "sampleCount": 1, "binaryName": "WXYC", "address": 4362084352,
            "subFrames": [
              {"binaryUUID": "APP", "offsetIntoBinaryTextSegment": 12288, "sampleCount": 1, "binaryName": "WXYC", "address": 4362088449}
            ]}
        ]}]}}
        """

        let event = try #require(MetricKitDiagnosticMapper.event(kind: .crash, json: Data(json.utf8)))
        let props = try #require(event.properties)
        let frames = try Self.frames(Self.exception(props))
        let images = try #require(props["$debug_images"] as? [[String: Any]])

        // 0x104002000 - 0x2000 = 0x104000000 and 0x104003001 - 0x3000 = 0x104000001.
        #expect(frames.count == 2)
        #expect(frames.allSatisfy { $0["image_addr"] as? String == "0x0000000104000000" })
        #expect(images.count == 1)
        #expect(images.first?["image_addr"] as? String == "0x0000000104000000")
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
        let exception = try Self.exception(props)
        #expect(exception["type"] as? String == "Crash")
        #expect(exception["value"] as? String == "Namespace SIGNAL (signal 11)")
    }

    private static func exception(_ props: [String: Any]) throws -> [String: Any] {
        try #require((props["$exception_list"] as? [[String: Any]])?.first)
    }

    private static func frames(_ exception: [String: Any]) throws -> [[String: Any]] {
        let stacktrace = try #require(exception["stacktrace"] as? [String: Any])
        #expect(stacktrace["type"] as? String == "raw")
        return try #require(stacktrace["frames"] as? [[String: Any]])
    }

    @Test("Malformed or stackless JSON produces no event", arguments: ["not json", "{}", #"{"callStackTree":{"callStacks":[]}}"#])
    func rejectsUnusableJSON(json: String) {
        #expect(MetricKitDiagnosticMapper.event(kind: .hang, json: Data(json.utf8)) == nil)
    }
}
