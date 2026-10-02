//
//  SimulatorCodeSigningTests.swift
//  WXYC
//
//  Pins that the project never turns code signing off for a build. An unsigned
//  simulator build carries no resource seal, and SpringBoard will not render a
//  launch storyboard out of an unsealed bundle: it fails validation, denylists
//  the app, and every launch from then on starts from solid black instead of
//  `LaunchScreen.storyboard`. Nothing in the build or the app reports it. The
//  simulator just stops showing what a device shows at launch, which is how
//  two investigations of launch-time appearance reached conclusions that only
//  held on the simulator (WXYC/wxyc-ios-64#1137).
//
//  Source-scanning rather than behavioural, because the seal cannot be
//  asserted from in here: `scripts/test-affected.sh` and the CI workflows pass
//  `CODE_SIGNING_ALLOWED=NO` on the command line, so this test's own host is
//  built unsigned on every gated run. What can be checked is that the project
//  does not make that choice for everyone else — a plain `xcodebuild build`,
//  or Run in Xcode.
//
//  Created by Jake Bromberg on 10/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing

@Suite("Simulator code signing")
struct SimulatorCodeSigningTests {
    /// Located relative to this file so the test moves with the target rather
    /// than depending on a bundle resource.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // WXYCTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // iOS
        .deletingLastPathComponent()  // WXYC
        .deletingLastPathComponent()  // repository root

    private static let projectFile = repositoryRoot
        .appendingPathComponent("WXYC.xcodeproj/project.pbxproj")

    /// Every file the project's build settings come from: the project file
    /// and the xcconfigs its configurations are based on.
    private static func buildSettingSources() throws -> [URL] {
        let xcconfigs = try FileManager.default
            .contentsOfDirectory(
                at: repositoryRoot.appendingPathComponent("WXYC/Configuration"),
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "xcconfig" }
        return [projectFile] + xcconfigs
    }

    /// Whether `line` assigns `NO` to `CODE_SIGNING_ALLOWED`, conditional or
    /// not, in either pbxproj (`"KEY[sdk=…]" = NO;`) or xcconfig
    /// (`KEY[sdk=…] = NO`) syntax. The value is whatever follows the last `=`,
    /// since a condition carries one of its own.
    private static func disablesSigning(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//"), trimmed.contains("CODE_SIGNING_ALLOWED") else { return false }
        let value = trimmed
            .split(separator: "=")
            .last?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t;\""))
        return value == "NO"
    }

    @Test("No build configuration turns code signing off")
    func noConfigurationDisablesSigning() throws {
        var offenders: [String] = []
        for source in try Self.buildSettingSources() {
            let lines = try String(contentsOf: source, encoding: .utf8).split(separator: "\n")
            offenders += lines
                .filter(Self.disablesSigning)
                .map { "\(source.lastPathComponent): \($0.trimmingCharacters(in: .whitespaces))" }
        }

        #expect(
            offenders.isEmpty,
            """
            Code signing is turned off in the project's own build settings:

            \(offenders.joined(separator: "\n"))

            An unsigned simulator build has no resource seal, so SpringBoard \
            rejects LaunchScreen.storyboard ("Resource validation error: \
            Security error -67056"), denylists the app, and the launch screen \
            is solid black from then on. Launch-time appearance measured on \
            such a build is not what a device shows — see \
            WXYC/wxyc-ios-64#1137.

            Simulator builds sign ad hoc and need no certificate or profile. \
            To skip signing for one invocation, pass CODE_SIGNING_ALLOWED=NO \
            on the xcodebuild command line, as scripts/test-affected.sh does.
            """
        )
    }

    /// Without this, a project file that moved or could not be read as build
    /// settings would leave the scan above with nothing to find, and it would
    /// pass having checked nothing.
    @Test("The scan reads the real project file")
    func scanIsNotVacuous() throws {
        let project = try String(contentsOf: Self.projectFile, encoding: .utf8)
        #expect(project.contains("isa = XCBuildConfiguration;"))
        #expect(project.contains("CODE_SIGN_STYLE = Automatic;"))
    }
}
