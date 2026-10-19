//
//  MetricKitDiagnosticMapper.swift
//  Analytics
//
//  Maps the JSON representation of an MXHangDiagnostic or MXCrashDiagnostic to
//  a PostHog `$exception` event. Works on JSON so fixtures can stand in for
//  MetricKit payloads, which cannot be constructed in tests.
//
//  Created by Jake Bromberg on 10/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Builds PostHog `$exception` events from MetricKit diagnostics.
///
/// The frame and debug-image shapes follow what posthog-ios's own crash processor emits
/// (`PostHogStackFrame` and `PostHogBinaryImageInfo`), because PostHog's error-tracking
/// processor reads a frame as Apple only when it says `platform: "apple"`, and symbolicates
/// it only by matching the frame's `image_addr` to an entry in the event's `$debug_images`.
/// They are not identical: these frames also carry `image_uuid`, which posthog-ios frames do
/// not, and these debug images carry no `image_size`, which posthog-ios images do.
public enum MetricKitDiagnosticMapper {
    public enum Kind: String, Sendable {
        case hang
        case crash
    }

    /// The most frames one stack carries by default: a backstop that keeps the frames nearest
    /// the crash or hang site and drops the oldest ones.
    ///
    /// The default cannot trigger on a real payload. Each frame nests two JSON levels deep (an
    /// object inside its parent's `subFrames` array), and `JSONSerialization` rejects JSON nested
    /// more than 512 levels. So a stack deeper than about 254 frames fails to parse first, and
    /// that diagnostic is dropped at parse time.
    public static let maxFrames = 256

    /// Builds an ``ExceptionEvent`` from one diagnostic's `jsonRepresentation()`.
    ///
    /// The stack is the attributed thread's (the first thread when none is attributed). A crash
    /// thread's call stack is a single chain, so the stack is that thread's full backtrace. A hang
    /// thread's call stack is a tree of samples, so the stack follows the most-sampled sub-frame
    /// at each level. PostHog wants frames oldest first, with the crash or hang site last. A hang
    /// stack already runs that way. A crash stack runs the other way: its root frame is the crash
    /// site and its sub-frames walk out to dyld's `start`, so the mapper reverses it. Other threads
    /// are not sent.
    /// - Parameters:
    ///   - kind: Whether the JSON is a hang or a crash diagnostic.
    ///   - json: The diagnostic's `jsonRepresentation()`.
    ///   - appBinaryName: The app's executable name. Frames in that binary are marked `in_app`.
    ///   - period: The payload's time range, which is when the diagnostic happened.
    ///   - maxFrames: The most frames the stack carries; see ``maxFrames``.
    /// - Returns: `nil` when the JSON is malformed or carries no call stack.
    public static func event(
        kind: Kind,
        json: Data,
        appBinaryName: String? = nil,
        period: DateInterval? = nil,
        maxFrames: Int = maxFrames
    ) -> ExceptionEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tree = root["callStackTree"] as? [String: Any],
              let stacks = tree["callStacks"] as? [[String: Any]],
              let stack = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first
        else {
            return nil
        }

        var rawFrames: [[String: Any]] = []
        var level = stack["callStackRootFrames"] as? [[String: Any]] ?? []
        while let frame = level.max(by: { sampleCount($0) < sampleCount($1) }) {
            rawFrames.append(frame)
            level = frame["subFrames"] as? [[String: Any]] ?? []
        }
        guard !rawFrames.isEmpty else {
            return nil
        }
        if kind == .crash {
            rawFrames.reverse()
        }
        let frames = rawFrames.suffix(maxFrames).map { Frame($0) }

        let metaData = root["diagnosticMetaData"] as? [String: Any] ?? [:]
        let exception: [String: any Sendable] = [
            "type": kind == .hang ? "AppHang" : "Crash",
            "value": value(kind: kind, metaData: metaData),
            "mechanism": ["type": "metrickit", "handled": false, "synthetic": false] as [String: any Sendable],
            "stacktrace": [
                "type": "raw",
                "frames": frames.map { $0.dictionary(appBinaryName: appBinaryName) },
            ] as [String: any Sendable],
        ]
        return ExceptionEvent(
            source: "metrickit",
            diagnosticKind: kind.rawValue,
            // A hang the app recovers from is not a crash; only a crash is fatal.
            level: kind == .crash ? "fatal" : "error",
            exceptionList: [exception],
            debugImages: debugImages(frames),
            additionalProperties: properties(metaData: metaData, period: period)
        )
    }

    // MARK: - Frames

    /// One MetricKit frame. The image load address is the frame's address minus its offset
    /// into the binary's text segment, as Sentry's MetricKit integration derives it, aligned down
    /// to the 4 KiB page. A caller frame's return address yields the image base plus one byte,
    /// where a leaf frame yields the base itself, so without the alignment two frames of one binary
    /// carry different addresses and only one matches the binary's `$debug_images` entry.
    private struct Frame {
        let address: UInt64?
        let binaryName: String?
        let binaryUUID: String?
        let imageAddress: UInt64?

        init(_ json: [String: Any]) {
            address = (json["address"] as? NSNumber)?.uint64Value
            binaryName = json["binaryName"] as? String
            binaryUUID = json["binaryUUID"] as? String
            let offset = (json["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value
            if let address, let offset, binaryUUID != nil, offset <= address {
                imageAddress = (address - offset) & ~0xFFF
            } else {
                imageAddress = nil
            }
        }

        func dictionary(appBinaryName: String?) -> [String: any Sendable] {
            var result: [String: any Sendable] = [
                "platform": "apple",
                "in_app": binaryName != nil && binaryName == appBinaryName,
            ]
            if let address {
                result["instruction_addr"] = hex(address)
            }
            if let binaryName {
                result["module"] = binaryName
                result["package"] = binaryName
            }
            if let imageAddress {
                result["image_addr"] = hex(imageAddress)
            }
            if let binaryUUID {
                result["image_uuid"] = binaryUUID
            }
            return result
        }
    }

    /// One `$debug_images` entry per binary the frames reference, in first-seen order.
    private static func debugImages(_ frames: [Frame]) -> [[String: any Sendable]] {
        var seen = Set<String>()
        var images: [[String: any Sendable]] = []
        for frame in frames {
            guard let uuid = frame.binaryUUID, let imageAddress = frame.imageAddress, seen.insert(uuid).inserted else {
                continue
            }
            var image: [String: any Sendable] = [
                "type": "macho",
                "debug_id": uuid,
                "image_addr": hex(imageAddress),
            ]
            if let name = frame.binaryName {
                image["code_file"] = name
            }
            images.append(image)
        }
        return images
    }

    private static func hex(_ address: UInt64) -> String {
        String(format: "0x%016llx", address)
    }

    private static func sampleCount(_ frame: [String: Any]) -> Int {
        frame["sampleCount"] as? Int ?? 0
    }

    // MARK: - Exception value and properties

    /// The exception's value. It holds only what identifies the failure, so one hang or crash
    /// site groups into one issue; per-occurrence details go in ``properties(metaData:period:)``.
    private static func value(kind: Kind, metaData: [String: Any]) -> String {
        switch kind {
        case .hang:
            return "App hang"
        case .crash:
            let reason = metaData["terminationReason"] as? String ?? "Crash"
            return metaData["signal"].map { "\(reason) (signal \($0))" } ?? reason
        }
    }

    private static func properties(metaData: [String: Any], period: DateInterval?) -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        if let duration = metaData["hangDuration"] as? String {
            result["hang_duration"] = duration
        }
        if let version = metaData["appVersion"] as? String {
            result["diagnostic_app_version"] = version
        }
        if let build = metaData["appBuildVersion"] as? String {
            result["diagnostic_app_build"] = build
        }
        if let period {
            result["diagnostic_period_start"] = period.start.formatted(.iso8601)
            result["diagnostic_period_end"] = period.end.formatted(.iso8601)
        }
        return result
    }
}
