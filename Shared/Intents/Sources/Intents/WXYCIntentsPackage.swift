//
//  WXYCIntentsPackage.swift
//  Intents
//
//  Declares the WXYCIntents module as an AppIntentsPackage so the system's
//  metadata indexer discovers intents defined here. Without this, intents
//  in external packages are invisible to Siri and Spotlight even when
//  registered via AppShortcutsProvider.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import AppIntents

public struct WXYCIntentsPackage: AppIntentsPackage { }
