//
//  RepeatingTimer.swift
//  PartyHorn
//
//  Repeating timer utility for animation timing.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

final class RepeatingTimer {
    private var timer: DispatchSourceTimer?
    private let queue: DispatchQueue
    private let initialDelay: TimeInterval
    private let interval: TimeInterval
    private let block: () -> Void
    private var isRunning = false

    init(initialDelay: TimeInterval, interval: TimeInterval, queue: DispatchQueue = .main, block: @escaping () -> Void) {
        self.initialDelay = initialDelay
        self.interval = interval
        self.queue = queue
        self.block = block
    }

    func start() {
        guard !isRunning else { return }
        print("timer starting")
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + initialDelay, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.block()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        guard isRunning else { return }
        print("timer stopping")
        timer?.cancel()
        timer = nil
        isRunning = false
    }

    deinit {
        stop()
    }
}
