//
//  RemoteCommandTargetRegistry.swift
//  Playback
//
//  Pairs remote-command target tokens with the commands that issued them.
//
//  Created by Jake Bromberg on 08/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import MediaPlayer

/// Records every remote-command target alongside the command that issued it, so
/// teardown can remove exactly what was registered.
///
/// `removeTarget(_:)` only unregisters a token from the command that returned it —
/// sending a token to any other command is a silent no-op. A flat array of tokens
/// therefore cannot be unwound: it has lost the one fact teardown needs. Collecting
/// tokens that way invites the failure this type exists to prevent, where teardown
/// iterates the tokens against a *hardcoded* list of commands and quietly leaks the
/// targets of every command missing from that list.
///
/// Leaks here are not bounded by the owner's lifetime: the system command centre is
/// `MPRemoteCommandCenter.shared()`, a process-global, so a target that outlives its
/// controller keeps responding to Lock Screen and Control Center events, and stacks
/// another handler each time a controller is built.
public struct RemoteCommandTargetRegistry {
    private var entries: [(command: any RemoteCommandProtocol, token: Any)] = []

    public init() {}

    /// The number of targets currently registered.
    public var count: Int { entries.count }

    /// Registers `handler` on `command` and records the returned token against it.
    public mutating func register(
        _ command: any RemoteCommandProtocol,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        entries.append((command, command.addTarget(handler: handler)))
    }

    /// Removes every registered target from the command that issued it, and empties
    /// the registry. Idempotent: a second call has nothing left to remove.
    public mutating func removeAll() {
        for entry in entries {
            entry.command.removeTarget(entry.token)
        }
        entries.removeAll()
    }
}
