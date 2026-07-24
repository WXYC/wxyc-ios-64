//
//  ReindexHandlerTests.swift
//  WXYCIntents
//
//  Shared `.serialized` parent for the F3 `IndexedEntityQuery` reindex-handler
//  suites (`PlaycutEntityQueryReindexTests`, `ConcertEntityQueryReindexTests`),
//  nested below as `ReindexHandlerTests.Playcut` / `ReindexHandlerTests.Concert`.
//
//  Both sibling suites register `any AnalyticsService` (and other
//  `@Dependency`-backed seams) directly onto the process-global
//  `AppDependencyManager.shared` registry, keyed by type. Each suite's own
//  `.serialized` trait only serializes the tests *within* that suite — it does
//  nothing to stop Swift Testing's default parallel scheduler from running a
//  `PlaycutEntityQueryReindexTests` test concurrently with a
//  `ConcertEntityQueryReindexTests` test, and both register the same
//  `any AnalyticsService` type. A race there means one suite's assertion can
//  observe the other suite's `MockStructuredAnalytics` — an intermittent flake
//  discovered in #622's review.
//
//  Swift Testing's `.serialized` trait, applied to a suite, also governs that
//  suite's descendant suites: nesting both reindex suites under this common
//  parent and moving the trait here (removing it from the two children) makes
//  every test under `ReindexHandlerTests` mutually exclusive — not just
//  within each child suite, but across them — closing the
//  `AppDependencyManager.shared` race without inventing a per-test
//  registration mechanism AppIntents' `@Dependency` doesn't support (its
//  resolution is a `AppDependencyManager.shared` type lookup; there is no
//  per-instance seam to use instead).
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing

@Suite("F3 reindex handlers (shared AppDependencyManager serialization)", .serialized)
struct ReindexHandlerTests {}
