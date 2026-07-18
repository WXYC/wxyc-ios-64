//
//  click.swift
//  WXYC
//
//  Posts a synthetic left mouse click or drag at host-screen coordinates.
//  Used by driver.sh to tap/swipe the iOS simulator: cliclick/idb are not
//  installed, System Events "click at" fails (-25204), and system python3
//  lacks Quartz — `swift click.swift` is the dependency-free path that works.
//
//  Usage:
//    swift click.swift <x> <y>              # click
//    swift click.swift <x> <y> press        # long press (1s hold)
//    swift click.swift <x> <y> <x2> <y2>    # drag from (x,y) to (x2,y2)
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Foundation

func post(_ type: CGEventType, at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(30_000)
}

let rawArgs = Array(CommandLine.arguments.dropFirst())
let isPress = rawArgs.last == "press"
let args = rawArgs.compactMap(Double.init)
switch args.count {
case 2:
    let p = CGPoint(x: args[0], y: args[1])
    post(.leftMouseDown, at: p)
    usleep(isPress ? 1_000_000 : 30_000)
    post(.leftMouseUp, at: p)
case 4:
    let from = CGPoint(x: args[0], y: args[1])
    let to = CGPoint(x: args[2], y: args[3])
    post(.leftMouseDown, at: from)
    // Interpolate so the gesture recognizer sees a continuous drag, not a warp.
    for step in 1...12 {
        let t = Double(step) / 12
        post(.leftMouseDragged, at: CGPoint(x: from.x + (to.x - from.x) * t,
                                            y: from.y + (to.y - from.y) * t))
    }
    post(.leftMouseUp, at: to)
default:
    FileHandle.standardError.write(Data("usage: swift click.swift <x> <y> [<x2> <y2>]\n".utf8))
    exit(1)
}
