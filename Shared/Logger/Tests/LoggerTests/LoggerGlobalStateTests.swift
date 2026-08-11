//
//  LoggerGlobalStateTests.swift
//  Logger
//
//  Umbrella suite nesting every LoggerTests suite that reads or mutates
//  process-global state (LoggerConfiguration.shared, Logger's registered
//  destinations, ErrorReporting.shared). `.serialized` on a suite only
//  orders that suite's own tests; it does not stop sibling top-level suites
//  from running concurrently and racing on shared statics. Swift Testing's
//  `.serialized` trait cascades to nested sub-suites, so nesting every
//  global-state suite under this one parent serializes all of them against
//  each other, closing that gap.
//
//  Created by Jake Bromberg on 08/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing

@Suite("Logger global state", .serialized)
struct LoggerGlobalStateTests {}
