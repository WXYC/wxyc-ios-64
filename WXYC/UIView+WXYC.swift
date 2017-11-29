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

extension UIImage {
    static var defaultNowPlayingInfoCenterImage: UIImage {
        if DispatchQueue.main == OperationQueue.current?.underlyingQueue {
            return makeImage()
        } else {
            return DispatchQueue.main.sync(execute: makeImage)
        }
    }
    
    private static func makeImage() -> UIImage {
        let backgroundView = UIImageView(image: #imageLiteral(resourceName: "background"))
        let logoView = UIImageView(image: #imageLiteral(resourceName: "logo"))
        logoView.contentMode = .scaleAspectFit
        
        let width = UIScreen.main.bounds.width
        backgroundView.frame = CGRect(x: 0, y: 0, width: width, height: width)
        logoView.frame = backgroundView.frame
        
        backgroundView.addSubview(logoView)
        
        return backgroundView.snapshot()!
    }
}
