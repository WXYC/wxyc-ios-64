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

public enum MetricKitDiagnosticMapper {
    public enum Kind: String, Sendable {
        case hang
        case crash
    }

    /// Builds an ``ExceptionEvent`` from one diagnostic's `jsonRepresentation()`.
    ///
    /// The frames come from the attributed thread's call stack (the first one when none is
    /// attributed), following the heaviest sub-frame at each level, oldest frame first.
    /// - Returns: `nil` when the JSON is malformed or carries no call stack.
    public static func event(kind: Kind, json: Data) -> ExceptionEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let tree = root["callStackTree"] as? [String: Any],
              let stacks = tree["callStacks"] as? [[String: Any]],
              let stack = stacks.first(where: { $0["threadAttributed"] as? Bool == true }) ?? stacks.first
        else { return nil }

        var frames: [[String: any Sendable]] = []
        var level = stack["callStackRootFrames"] as? [[String: Any]] ?? []
        while let frame = level.max(by: { sampleCount($0) < sampleCount($1) }) {
            frames.append(self.frame(frame))
            level = frame["subFrames"] as? [[String: Any]] ?? []
        }
        guard !frames.isEmpty else { return nil }

        let metaData = root["diagnosticMetaData"] as? [String: Any] ?? [:]
        let exception: [String: any Sendable] = [
            "type": kind == .hang ? "AppHang" : "Crash",
            "value": value(kind: kind, metaData: metaData),
            "mechanism": ["type": "metrickit", "handled": false] as [String: any Sendable],
            "stacktrace": ["type": "raw", "frames": frames] as [String: any Sendable],
        ]
        return ExceptionEvent(source: "metrickit", diagnosticKind: kind.rawValue, exceptionList: [exception])
    }

    private static func sampleCount(_ frame: [String: Any]) -> Int {
        frame["sampleCount"] as? Int ?? 0
    }

    private static func frame(_ frame: [String: Any]) -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        if let address = frame["address"] as? Int { result["instruction_addr"] = "0x" + String(address, radix: 16) }
        if let name = frame["binaryName"] as? String { result["module"] = name }
        if let uuid = frame["binaryUUID"] as? String { result["debug_id"] = uuid }
        if let offset = frame["offsetIntoBinaryTextSegment"] as? Int { result["image_offset"] = offset }
        return result
    }

    private static func value(kind: Kind, metaData: [String: Any]) -> String {
        switch kind {
        case .hang:
            return metaData["hangDuration"].map { "App hung for \($0)" } ?? "App hang"
        case .crash:
            let reason = metaData["terminationReason"] as? String ?? "Crash"
            return metaData["signal"].map { "\(reason) (signal \($0))" } ?? reason
        }
    }
}
