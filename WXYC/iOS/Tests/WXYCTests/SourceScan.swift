//
//  SourceScan.swift
//  WXYC
//
//  Shared support for tests that assert against Swift source as text because
//  the invariant they check has no runtime seam. `LaunchSequenceOrderingTests`
//  explains why source-scanning is the deliberate choice for its call site,
//  not a scanning habit; `FeatureFlagProviderWiringTests` reuses the same
//  scanner for a second call site.
//
//  Created by Jake Bromberg on 08/27/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing

enum SourceScan {
    /// Locates the first line of `url` (after trimming whitespace) matching
    /// `start`, then returns the trimmed, `//`-comment-stripped lines from
    /// there through the line where a running count of `open` characters
    /// minus `close` characters first returns to zero.
    ///
    /// Depth-matching rather than a fixed line count means a nested `open`/
    /// `close` inside the region — a brace in a closure, a paren in a nested
    /// call — can't end the scan early.
    ///
    /// Refuses the result (an `#expect` failure, not a thrown error, so the
    /// caller's other assertions still run) if the bounded region contains a
    /// block comment: this scan only understands `//`, so a `/* */` inside
    /// the region could hide a match from it or contribute a line that looks
    /// like one, and the result would no longer be trustworthy.
    /// `LaunchSequenceOrderingTests` was burned by exactly this shape of bug
    /// once already — a doc comment describing the very call this test
    /// searches for read as a match — before it learned to skip `//` lines;
    /// a block comment would reopen the same hole in a form a `//`-only scan
    /// cannot see on its own.
    static func boundedLines(
        of url: URL,
        start startPredicate: (String) -> Bool,
        startNotFoundMessage: Comment,
        open: Character,
        close: Character
    ) throws -> [String] {
        let all = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Resolved before `#require` rather than inside it: the macro expansion
        // captures its argument expression, which a non-escaping closure
        // parameter cannot survive ("may allow it to escape").
        let startIndex = all.firstIndex(where: startPredicate)
        let start = try #require(startIndex, startNotFoundMessage)

        // Brace/paren-count from `start` to its matching close so a later,
        // unrelated `open`/`close` pair can't be mistaken for this one's.
        var depth = 0
        var end = all.count - 1
        for index in start..<all.count {
            let line = all[index]
            guard !line.hasPrefix("//") else { continue }
            depth += line.filter { $0 == open }.count
            depth -= line.filter { $0 == close }.count
            if depth == 0 {
                end = index
                break
            }
        }

        let region = Array(all[start...end])

        #expect(
            !region.contains { $0.contains("/*") },
            """
            \(url.lastPathComponent) contains a block comment in the scanned \
            region. This scan only strips `//` lines, so its result is no \
            longer trustworthy — teach it to skip block comments before \
            relying on it again.
            """
        )

        return region.filter { !$0.hasPrefix("//") }
    }
}
