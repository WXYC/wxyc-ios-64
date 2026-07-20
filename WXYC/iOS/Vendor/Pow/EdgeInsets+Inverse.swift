//
//  Backfills the `EdgeInsets.inverse` helper that Pow's SprayEffect relies on
//  but which lives outside the vendored change-effect subset.
//  Pow — https://github.com/EmergeTools/Pow (MIT). See LICENSE in this directory.
//

import SwiftUI

internal extension EdgeInsets {
    var inverse: Self {
        EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing)
    }
}
