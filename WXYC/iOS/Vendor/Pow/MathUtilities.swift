//
//  Vendored from Pow — https://github.com/EmergeTools/Pow
//  Copyright (c) 2023 Emerge Tools, Inc. MIT License. See LICENSE in this directory.
//
//  Trimmed to the change-effect subset used by WXYC (DEBUG previews and unused helpers removed).
//

import Foundation
import CoreGraphics

internal func rubberClamp(_ min: CGFloat, _ value: CGFloat, _ max: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
    let clamped = clamp(min, value, max)

    let delta = abs(clamped - value)

    guard delta != 0 else {
        return value
    }

    let sign: CGFloat = clamped > value ? -1 : 1

    let range = (max - min)

    return clamped + sign * (1.0 - (1.0 / ((delta * coefficient / range) + 1.0))) * range
}

internal func clamp<C: Comparable>(_ min: C, _ value: C, _ max: C) -> C {
    Swift.max(min, Swift.min(value, max))
}

internal func clamp<F: FloatingPoint>(_ value: F) -> F {
    clamp(0, value, 1)
}
