//
//  AppSession.swift
//  WatchXYC App
//
//  Created by Jake Bromberg on 2/28/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Logger
import Core

private let SessionStartTimer = Timer.start()

@discardableResult
public func validateCollection(_ collection: any Collection, label: String) -> Bool {
    if collection.isEmpty {
        Log(.info, "\(label) is empty. Session duration: \(SessionStartTimer.duration())")
        return false
    }
    
    Log(.info, "\(label) is valid. Session duration: \(SessionStartTimer.duration())")
    return true
}
