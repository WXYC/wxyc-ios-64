//
//  RepeatingTimer.swift
//  Party Horn
//
//  Created by Jake Bromberg on 8/17/25.
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
