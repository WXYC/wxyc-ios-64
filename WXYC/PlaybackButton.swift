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
    
    private static let kAnimationKey = "playbackValue"
    private static let kAnimationIdentifier = "playbackLayerAnimation"
    
    private var adjustMarginValue: CGFloat = 0
    private var contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    var status = PlaybackButtonState.paused
    @objc var playbackValue: CGFloat = 1.0 {
        didSet {
            setNeedsDisplay()
        }
    }
    var color = UIColor.white
    var playbackAnimationDuration: CFTimeInterval = DefaultsPlaybackDuration
    
    override init() {
        super.init()
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
        if let playbackLayer = layer as? PlaybackLayer {
            self.adjustMarginValue = playbackLayer.adjustMarginValue
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
            if self.animation(forKey: PlaybackLayer.kAnimationIdentifier) != nil {
                self.removeAnimation(forKey: PlaybackLayer.kAnimationIdentifier)
            }
            
            let fromValue: CGFloat = self.playbackValue
            let toValue: CGFloat = status.value
            
            let animation = CABasicAnimation(keyPath: PlaybackLayer.kAnimationKey)
            animation.fromValue = fromValue
            animation.toValue = toValue
            animation.duration = self.playbackAnimationDuration
            animation.isRemovedOnCompletion = true
            animation.fillMode = kCAFillModeForwards
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            animation.delegate = self
            self.add(animation, forKey: PlaybackLayer.kAnimationIdentifier)
        } else {
            self.playbackValue = status.value
        }
    }
    
    override class func needsDisplay(forKey key: String) -> Bool {
        if key == PlaybackLayer.kAnimationKey {
            return true
        }
        return CALayer.needsDisplay(forKey: key)
    }
    
    override func draw(in context: CGContext) {
        let rect = context.boundingBoxOfClipPath
        let baseWidth = rect.width
        let baseHeight = rect.height
        let topMargin: CGFloat = self.contentEdgeInsets.top
        let leftMargin: CGFloat = self.contentEdgeInsets.left
        
        let drawHalfWidth: CGFloat = (baseWidth - leftMargin * 2) / 2.0
        let drawQuarterWidth: CGFloat = drawHalfWidth / 2.0
        let subtractWidth: CGFloat = drawHalfWidth - drawQuarterWidth
        let width: CGFloat = drawQuarterWidth + subtractWidth * self.playbackValue
        
        let playingMargin: CGFloat = drawQuarterWidth / 2.0 * self.adjustMarginValue
        let pausingMargin: CGFloat = drawQuarterWidth / 2.0
        let subtractMargin: CGFloat = playingMargin - pausingMargin
        let adjustMargin: CGFloat = pausingMargin + subtractMargin * self.playbackValue
        
        let height: CGFloat = baseHeight - topMargin * 2
        let h1: CGFloat = height / 4.0 * self.playbackValue
        let h2: CGFloat = height / 2.0 * self.playbackValue
        
        context.move(to: CGPoint(x: leftMargin + adjustMargin, y: topMargin))
        context.addLine(to: CGPoint(x: leftMargin + adjustMargin + width, y: topMargin + h1))
        context.addLine(to: CGPoint(x: leftMargin + adjustMargin + width, y: topMargin + height - h1))
        context.addLine(to: CGPoint(x: leftMargin + adjustMargin, y: topMargin + height))
        
        context.move(to: CGPoint(x: leftMargin + drawHalfWidth + adjustMargin, y: topMargin + h1))
        context.addLine(to: CGPoint(x: leftMargin + drawHalfWidth + adjustMargin + width, y: topMargin + h2))
        context.addLine(to: CGPoint(x: leftMargin + drawHalfWidth + adjustMargin + width, y: topMargin + height - h2))
        context.addLine(to: CGPoint(x: leftMargin + drawHalfWidth + adjustMargin, y: topMargin + height - h1))
        
        context.setFillColor(self.color.cgColor)
        context.fillPath()
    }
}

extension PlaybackLayer: CAAnimationDelegate {
    
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if flag {
            if self.animation(forKey: PlaybackLayer.kAnimationIdentifier) != nil {
                self.removeAnimation(forKey: PlaybackLayer.kAnimationIdentifier)
            }
            if let toValue : CGFloat = anim.value(forKey: "toValue") as? CGFloat {
                self.playbackValue = toValue
            }
        }
    }
}

@objc @IBDesignable class PlaybackButton : UIButton {
    private var playbackLayer: PlaybackLayer {
        return self.layer as! PlaybackLayer
    }
    
    var duration: CFTimeInterval = DefaultsPlaybackDuration {
        didSet {
            self.playbackLayer.playbackAnimationDuration = self.duration
        }
    }
    
    var status: PlaybackButtonState {
        get {
            return self.playbackLayer.status
        }
        set {
            self.playbackLayer.set(status: newValue, animated: true)
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
        self.playbackLayer.set(status: status, animated: animated)
    }
    
    override var tintColor: UIColor! {
        didSet {
            self.playbackLayer.color = tintColor
        }
    }
    
    override class var layerClass: AnyClass {
        return PlaybackLayer.self
    }
    
    private func addPlaybackLayer() {
        playbackLayer.frame = self.bounds
        playbackLayer.playbackValue = PlaybackButtonState.paused.value
        playbackLayer.color = self.tintColor
        playbackLayer.playbackAnimationDuration = self.duration
    }
}
