//
//  SpinningAnimation.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/24/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import UIKit

final class SpinningAnimation: CABasicAnimation {
    override init() {
        super.init()
        
        self.keyPath = "transform.rotation.z"
        self.duration = 2
        self.repeatCount = 100
        self.autoreverses = false
        self.fromValue = Float.pi / 3.0
        self.toValue = -0.0
        self.isRemovedOnCompletion = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension UIView {
    static let AnimationKey = "spinAnimation"
    
    func startSpin() {
        if self.layer.animation(forKey: UIView.AnimationKey) == nil {
            self.layer.add(SpinningAnimation(), forKey: UIView.AnimationKey)
        }
        
        self.resume(layer: self.layer)
    }
    
    func stopSpin() {
        self.pause(layer: self.layer)
    }
    
    private func pause(layer: CALayer) {
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0.0
        layer.timeOffset = pausedTime
    }
    
    private func resume(layer: CALayer) {
        let pausedTime = layer.timeOffset
        layer.speed = 1.0
        layer.timeOffset = 0.0
        layer.beginTime = 0.0
        
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
    }
}
