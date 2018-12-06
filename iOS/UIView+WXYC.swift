//
//  UIView+WXYC.swift
//  WXYC
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit.UIView

extension UIView {
    func snapshot() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, 0.0)
        
        defer {
            UIGraphicsEndImageContext()
        }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        layer.render(in: context)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        
        return image
    }
}
