//
//  InkingButton.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/7/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import UIKit

public class InkingButton: UIButton {
    private struct Animation {
        let fadeDuration: CFTimeInterval
        let scaleDuration: CFTimeInterval
        let scale: CGFloat
        let opacity: CGFloat
        
        static let InkIn  = Animation(fadeDuration: 0.075, scaleDuration: 0.075, scale: 1.0, opacity: 1.0)
        static let InkOut = Animation(fadeDuration: 0.200, scaleDuration: 0.500, scale: 0.6, opacity: 0.0)
    }
    
    private let rippleLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor(white: 0, alpha: 0.2).cgColor
        layer.transform = CATransform3DMakeScale(Animation.InkIn.scale, Animation.InkIn.scale, 1.0)
        layer.opacity = 0.0
        
        return layer
    }()
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        self.setUpViews()
    }
    
    private func setUpViews() {
        self.clipsToBounds = false
        self.layer.addSublayer(self.rippleLayer)
        self.layer.shadowRadius = 0.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
    }

    public override var isHighlighted: Bool {
        set {
            super.isHighlighted = newValue
            
            self.set(inked: newValue)
        }
        get {
            return super.isHighlighted
        }
    }
    
    private func set(inked: Bool) {
        let animation: Animation = inked ? .InkIn : .InkOut
        
        let scaleAnimation = CABasicAnimation()
        scaleAnimation.duration = animation.scaleDuration
        scaleAnimation.keyPath = "transform.scale"
        scaleAnimation.fromValue = self.rippleLayer.presentation()?.value(forKeyPath: "transform.scale")
        scaleAnimation.toValue = animation.scale
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnimation.fillMode = .forwards
        scaleAnimation.isRemovedOnCompletion = false
        
        self.rippleLayer.add(scaleAnimation, forKey: "scale")

        let alphaAnimation = CABasicAnimation()
        alphaAnimation.duration = animation.fadeDuration
        alphaAnimation.keyPath = "opacity"
        alphaAnimation.fromValue = self.rippleLayer.presentation()?.opacity
        alphaAnimation.toValue = animation.opacity
        alphaAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        alphaAnimation.fillMode = .forwards
        alphaAnimation.isRemovedOnCompletion = false

        self.rippleLayer.add(alphaAnimation, forKey: "opacity")
    }
    
    public override var isEnabled: Bool {
        set {
            super.isEnabled = isEnabled

            self.setNeedsLayout()
        }
        get {
            return super.isEnabled
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        self.rippleLayer.path = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.height).cgPath
        self.rippleLayer.bounds = self.bounds

        self.rippleLayer.position = self.bounds.midPoint
    }
}

extension CGRect {
    var midPoint: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}
