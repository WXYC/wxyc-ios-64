//
//  PlaybackButton.swift
//  PlaybackButton
//
//  Created by Yuji Hato on 1/1/16.
//  Copyright © 2016 dekatotoro. All rights reserved.
//


import UIKit

let DefaultsPlaybackDuration: CFTimeInterval = 0.24

@objc public enum PlaybackButtonState : Int {
    case paused
    case playing
    
    public var value: CGFloat {
        switch self {
        case .paused:
            return 1.0
        case .playing:
            return 0.0
        }
    }
}

@objc @IBDesignable class PlaybackLayer: CALayer {
    private static let AnimationKey = "playbackValue"
    private static let AnimationIdentifier = "playbackLayerAnimation"
    
    private var contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    var status: PlaybackButtonState = .paused
    
    @objc var playbackValue: CGFloat = 1.0 {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var color = UIColor.white
    var playbackAnimationDuration: CFTimeInterval = DefaultsPlaybackDuration
    
    override init() {
        super.init()
        
        self.backgroundColor = UIColor.clear.cgColor
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        if let playbackLayer = layer as? PlaybackLayer {
            self.status = playbackLayer.status
            self.playbackValue = playbackLayer.playbackValue
            self.color = playbackLayer.color
        }
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    deinit {
        self.removeAllAnimations()
    }
    
    func set(status: PlaybackButtonState, animated: Bool) {
        if self.status == status {
            return
        }
        
        self.status = status
        
        if animated {
            if self.animation(forKey: PlaybackLayer.AnimationIdentifier) != nil {
                self.removeAnimation(forKey: PlaybackLayer.AnimationIdentifier)
            }
            
            let fromValue: CGFloat = self.playbackValue
            let toValue: CGFloat = status.value
            
            let animation = CABasicAnimation(keyPath: PlaybackLayer.AnimationKey)
            animation.fromValue = fromValue
            animation.toValue = toValue
            animation.duration = self.playbackAnimationDuration
            animation.isRemovedOnCompletion = true
            animation.fillMode = CAMediaTimingFillMode.forwards
            animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            animation.delegate = self
            
            self.add(animation, forKey: PlaybackLayer.AnimationIdentifier)
        } else {
            self.playbackValue = status.value
        }
    }
    
    override class func needsDisplay(forKey key: String) -> Bool {
        if key == PlaybackLayer.AnimationKey {
            return true
        }
        return CALayer.needsDisplay(forKey: key)
    }
    
    override func draw(in context: CGContext) {
        context.clear(self.visibleRect)
        
        let rect = context.boundingBoxOfClipPath

        let halfWidth = rect.width / 2.0
        let eighthWidth = halfWidth / 2.0
        let sixteenthWidth: CGFloat = eighthWidth / 2.0
        let thirtySecondWidth: CGFloat = sixteenthWidth / 2.0

        let componentWidth: CGFloat = sixteenthWidth * (1 + self.playbackValue)
        let insetMargin: CGFloat = thirtySecondWidth * (1 - self.playbackValue)
        
        let firstHalfMargin: CGFloat = eighthWidth + insetMargin
        let secondHalfMargin = halfWidth + insetMargin

        let halfHeight = rect.height / 2.0
        let quarterHeight: CGFloat = halfHeight / 2.0
        let sixteenthHeight: CGFloat = halfHeight / 4.0
        
        let h1: CGFloat = sixteenthHeight * self.playbackValue
        let h2: CGFloat = quarterHeight * self.playbackValue
        
        context.move(to: CGPoint(x: firstHalfMargin, y: quarterHeight))
        context.addLine(to: CGPoint(x: firstHalfMargin + componentWidth, y: quarterHeight + h1))
        context.addLine(to: CGPoint(x: firstHalfMargin + componentWidth, y: quarterHeight + halfHeight - h1))
        context.addLine(to: CGPoint(x: firstHalfMargin, y: quarterHeight + halfHeight))
        
        context.move(to: CGPoint(x: secondHalfMargin, y: quarterHeight + h1))
        context.addLine(to: CGPoint(x: secondHalfMargin + componentWidth, y: quarterHeight + h2))
        context.addLine(to: CGPoint(x: secondHalfMargin + componentWidth, y: quarterHeight + halfHeight - h2))
        context.addLine(to: CGPoint(x: secondHalfMargin, y: quarterHeight + halfHeight - h1))
        
        context.setFillColor(self.color.cgColor)
        context.fillPath()
    }
}

extension PlaybackLayer: CAAnimationDelegate {
    
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag else {
            return
        }

        if self.animation(forKey: PlaybackLayer.AnimationIdentifier) != nil {
            self.removeAnimation(forKey: PlaybackLayer.AnimationIdentifier)
        }

        if let toValue: CGFloat = anim.value(forKey: "toValue") as? CGFloat {
            self.playbackValue = toValue
        }
    }
}

@objc @IBDesignable class PlaybackButton : UIButton {
    override var layer: PlaybackLayer {
        return super.layer as! PlaybackLayer
    }
    
    var duration: CFTimeInterval = DefaultsPlaybackDuration {
        didSet {
            self.layer.playbackAnimationDuration = self.duration
        }
    }
    
    var status: PlaybackButtonState {
        get {
            return self.layer.status
        }
        set {
            self.layer.set(status: newValue, animated: true)
        }
    }
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addPlaybackLayer()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.addPlaybackLayer()
    }
    
    func set(status: PlaybackButtonState, animated: Bool = true) {
        self.layer.set(status: status, animated: animated)
    }
    
    override var tintColor: UIColor! {
        didSet {
            self.layer.color = tintColor
        }
    }
    
    override class var layerClass: AnyClass {
        return PlaybackLayer.self
    }
    
    private func addPlaybackLayer() {
        layer.contentsScale = UIScreen.main.scale
        layer.frame = self.bounds
        layer.playbackValue = PlaybackButtonState.paused.value
        layer.color = self.tintColor
        layer.playbackAnimationDuration = self.duration
    }
}
