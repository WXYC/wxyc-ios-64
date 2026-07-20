//
//  Vendored from Pow — https://github.com/EmergeTools/Pow
//  Copyright (c) 2023 Emerge Tools, Inc. MIT License. See LICENSE in this directory.
//
//  Trimmed to the change-effect subset used by WXYC (DEBUG previews and unused helpers removed).
//

import Foundation
import SwiftUI
import Dispatch

public extension View {
    /// Applies the given change effect to this view when the specified value changes.
    ///
    /// - Parameters:
    ///   - effect: The effect to apply.
    ///   - value: A value to monitor for changes.
    ///   - isEnabled: A Boolean value that indicates whether the effect should be applied when the value changes.  Defaults to `true`.
    ///
    /// - Returns: A view that applies the effect to this view whenever value changes.
    @ViewBuilder
    func changeEffect<V: Equatable>(_ effect: AnyChangeEffect, value: V, isEnabled: @autoclosure @escaping () -> Bool = true) -> some View {
        modifier(HighlightChangeModifier(value, effect: effect, predicate: { _ in isEnabled() }))
    }
}

struct HighlightChangeModifier<Value: Equatable>: ViewModifier {
    var value: Value

    var effect: AnyChangeEffect

    var predicate: (Value) -> Bool

    @State
    private var changeCount: Int = 0

    @State
    private var lastUpdate: Date = .distantPast

    init(_ value: Value, effect: AnyChangeEffect, predicate: @escaping (Value) -> Bool) {
        self.value = value
        self.effect = effect
        self.predicate = predicate
    }

    func body(content: Content) -> some View {
        let t = effect.viewModifier(changeCount: changeCount)
        let cooldown = effect.cooldown
        let delay = effect.delay

        func update(_ newValue: Value) {
            guard predicate(newValue), value != newValue else { return }

            guard lastUpdate.timeIntervalSinceNow < -cooldown else { return }
            lastUpdate = .now

            changeCount += 1
        }

        return content
            .onChange(of: value) { newValue in
                if delay == 0 {
                    update(newValue)
                } else {
                    let when = DispatchQueue.SchedulerTimeType(DispatchTime.now() + delay)

                    DispatchQueue.main.schedule(after: when, tolerance: 0.016) {
                        update(newValue)
                    }
                }
            }
            .modifier(t)
    }
}
