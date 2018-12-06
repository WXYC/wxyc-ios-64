// The MIT License (MIT)
//
// Copyright (c) 2015 Meng To (meng@designcode.io)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit

public enum SpringAnimationCurve: String {
    case EaseIn
    case EaseOut
    case EaseInOut
    case Linear
    case Spring
    case EaseInSine
    case EaseOutSine
    case EaseInOutSine
    case EaseInQuad
    case EaseOutQuad
    case EaseInOutQuad
    case EaseInCubic
    case EaseOutCubic
    case EaseInOutCubic
    case EaseInQuart
    case EaseOutQuart
    case EaseInOutQuart
    case EaseInQuint
    case EaseOutQuint
    case EaseInOutQuint
    case EaseInExpo
    case EaseOutExpo
    case EaseInOutExpo
    case EaseInCirc
    case EaseOutCirc
    case EaseInOutCirc
    case EaseInBack
    case EaseOutBack
    case EaseInOutBack
}

public protocol Springable: class {
    var autostart: Bool  { get set }
    var autohide: Bool  { get set }
    var animation: SpringAnimation  { get set }
    var force: CGFloat  { get set }
    var delay: CGFloat { get set }
    var duration: CGFloat { get set }
    var damping: CGFloat { get set }
    var velocity: CGFloat { get set }
    var repeatCount: Float { get set }
    var x: CGFloat { get set }
    var y: CGFloat { get set }
    var scaleX: CGFloat { get set }
    var scaleY: CGFloat { get set }
    var rotate: CGFloat { get set }
    var opacity: CGFloat { get set }
    var animateFrom: Bool { get set }
    var curve: SpringAnimationCurve { get set }
    
    func animate()
    func animateNext(completion: @escaping () -> ())
    func animateTo()
    func animateToNext(completion: @escaping () -> ())
}

public enum SpringAnimation: String {
    case SlideLeft
    case SlideRight
    case SlideDown
    case SlideUp
    case SqueezeLeft
    case SqueezeRight
    case SqueezeDown
    case SqueezeUp
    case FadeIn
    case FadeOut
    case FadeOutIn
    case FadeInLeft
    case FadeInRight
    case FadeInDown
    case FadeInUp
    case ZoomIn
    case ZoomOut
    case Fall
    case Shake
    case Pop
    case FlipX
    case FlipY
    case Morph
    case Squeeze
    case Flash
    case Wobble
    case Swing
}

extension Springable where Self: UIView {
    func animatePreset() {
        alpha = 0.99
        switch self.animation {
        case .SlideLeft:
            x = 300*force
        case .SlideRight:
            x = -300*force
        case .SlideDown:
            y = -300*force
        case .SlideUp:
            y = 300*force
        case .SqueezeLeft:
            x = 300
            scaleX = 3*force
        case .SqueezeRight:
            x = -300
            scaleX = 3*force
        case .SqueezeDown:
            y = -300
            scaleY = 3*force
        case .SqueezeUp:
            y = 300
            scaleY = 3*force
        case .FadeIn:
            opacity = 0
        case .FadeOut:
            animateFrom = false
            opacity = 0
        case .FadeOutIn:
            let animation = CABasicAnimation()
            animation.keyPath = "opacity"
            animation.fromValue = 1
            animation.toValue = 0
            animation.timingFunction = self.timingFunction
            animation.duration = CFTimeInterval(duration)
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            animation.autoreverses = true
            layer.add(animation, forKey: "fade")
        case .FadeInLeft:
            opacity = 0
            x = 300*force
        case .FadeInRight:
            x = -300*force
            opacity = 0
        case .FadeInDown:
            y = -300*force
            opacity = 0
        case .FadeInUp:
            y = 300*force
            opacity = 0
        case .ZoomIn:
            opacity = 0
            scaleX = 2*force
            scaleY = 2*force
        case .ZoomOut:
            animateFrom = false
            opacity = 0
            scaleX = 2*force
            scaleY = 2*force
        case .Fall:
            animateFrom = false
            rotate = 15 * (CGFloat.pi / 180)
            y = 600*force
        case .Shake:
            let animation = CAKeyframeAnimation()
            animation.keyPath = "position.x"
            animation.values = [0, 30*force, -30*force, 30*force, 0]
            animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            animation.timingFunction = self.timingFunction
            animation.duration = CFTimeInterval(duration)
            animation.isAdditive = true
            animation.repeatCount = repeatCount
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(animation, forKey: "shake")
        case .Pop:
            let animation = CAKeyframeAnimation()
            animation.keyPath = "transform.scale"
            animation.values = [0, 0.2*force, -0.2*force, 0.2*force, 0]
            animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            animation.timingFunction = self.timingFunction
            animation.duration = CFTimeInterval(duration)
            animation.isAdditive = true
            animation.repeatCount = repeatCount
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(animation, forKey: "pop")
        case .FlipX:
            rotate = 0
            scaleX = 1
            scaleY = 1
            var perspective = CATransform3DIdentity
            perspective.m34 = -1.0 / layer.frame.size.width/2
            
            let animation = CABasicAnimation()
            animation.keyPath = "transform"
            animation.fromValue = NSValue(caTransform3D: CATransform3DMakeRotation(0, 0, 0, 0))
            animation.toValue = NSValue(caTransform3D:
                CATransform3DConcat(perspective, CATransform3DMakeRotation(CGFloat.pi, 0, 1, 0)))
            animation.duration = CFTimeInterval(duration)
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            animation.timingFunction = self.timingFunction
            layer.add(animation, forKey: "3d")
        case .FlipY:
            var perspective = CATransform3DIdentity
            perspective.m34 = -1.0 / layer.frame.size.width/2
            
            let animation = CABasicAnimation()
            animation.keyPath = "transform"
            animation.fromValue = NSValue(caTransform3D:
                CATransform3DMakeRotation(0, 0, 0, 0))
            animation.toValue = NSValue(caTransform3D:
                CATransform3DConcat(perspective,CATransform3DMakeRotation(CGFloat.pi, 1, 0, 0)))
            animation.duration = CFTimeInterval(duration)
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            animation.timingFunction = self.timingFunction
            layer.add(animation, forKey: "3d")
        case .Morph:
            let morphX = CAKeyframeAnimation()
            morphX.keyPath = "transform.scale.x"
            morphX.values = [1, 1.3*force, 0.7, 1.3*force, 1]
            morphX.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            morphX.timingFunction = self.timingFunction
            morphX.duration = CFTimeInterval(duration)
            morphX.repeatCount = repeatCount
            morphX.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(morphX, forKey: "morphX")
            
            let morphY = CAKeyframeAnimation()
            morphY.keyPath = "transform.scale.y"
            morphY.values = [1, 0.7, 1.3*force, 0.7, 1]
            morphY.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            morphY.timingFunction = self.timingFunction
            morphY.duration = CFTimeInterval(duration)
            morphY.repeatCount = repeatCount
            morphY.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(morphY, forKey: "morphY")
        case .Squeeze:
            let morphX = CAKeyframeAnimation()
            morphX.keyPath = "transform.scale.x"
            morphX.values = [1, 1.5*force, 0.5, 1.5*force, 1]
            morphX.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            morphX.timingFunction = self.timingFunction
            morphX.duration = CFTimeInterval(duration)
            morphX.repeatCount = repeatCount
            morphX.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(morphX, forKey: "morphX")
            
            let morphY = CAKeyframeAnimation()
            morphY.keyPath = "transform.scale.y"
            morphY.values = [1, 0.5, 1, 0.5, 1]
            morphY.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            morphY.timingFunction = self.timingFunction
            morphY.duration = CFTimeInterval(duration)
            morphY.repeatCount = repeatCount
            morphY.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(morphY, forKey: "morphY")
        case .Flash:
            let animation = CABasicAnimation()
            animation.keyPath = "opacity"
            animation.fromValue = 1
            animation.toValue = 0
            animation.duration = CFTimeInterval(duration)
            animation.repeatCount = repeatCount * 2.0
            animation.autoreverses = true
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(animation, forKey: "flash")
        case .Wobble:
            let animation = CAKeyframeAnimation()
            animation.keyPath = "transform.rotation"
            animation.values = [0, 0.3*force, -0.3*force, 0.3*force, 0]
            animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            animation.duration = CFTimeInterval(duration)
            animation.isAdditive = true
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(animation, forKey: "wobble")
            
            let x = CAKeyframeAnimation()
            x.keyPath = "position.x"
            x.values = [0, 30*force, -30*force, 30*force, 0]
            x.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            x.timingFunction = self.timingFunction
            x.duration = CFTimeInterval(duration)
            x.isAdditive = true
            x.repeatCount = repeatCount
            x.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(x, forKey: "x")
        case .Swing:
            let animation = CAKeyframeAnimation()
            animation.keyPath = "transform.rotation"
            animation.values = [0, 0.3*force, -0.3*force, 0.3*force, 0]
            animation.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
            animation.duration = CFTimeInterval(duration)
            animation.isAdditive = true
            animation.beginTime = CACurrentMediaTime() + CFTimeInterval(delay)
            layer.add(animation, forKey: "swing")
        }
    }
    
    var timingFunction: CAMediaTimingFunction {
        switch self.curve {
        case .EaseIn: return CAMediaTimingFunction(name: .easeIn)
        case .EaseOut: return CAMediaTimingFunction(name: .easeOut)
        case .EaseInOut: return CAMediaTimingFunction(name: .easeInEaseOut)
        case .Linear: return CAMediaTimingFunction(name: .linear)
        case .Spring: return CAMediaTimingFunction(controlPoints: 0.5, 1.1+Float(force/3), 1, 1)
        case .EaseInSine: return CAMediaTimingFunction(controlPoints: 0.47, 0, 0.745, 0.715)
        case .EaseOutSine: return CAMediaTimingFunction(controlPoints: 0.39, 0.575, 0.565, 1)
        case .EaseInOutSine: return CAMediaTimingFunction(controlPoints: 0.445, 0.05, 0.55, 0.95)
        case .EaseInQuad: return CAMediaTimingFunction(controlPoints: 0.55, 0.085, 0.68, 0.53)
        case .EaseOutQuad: return CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
        case .EaseInOutQuad: return CAMediaTimingFunction(controlPoints: 0.455, 0.03, 0.515, 0.955)
        case .EaseInCubic: return CAMediaTimingFunction(controlPoints: 0.55, 0.055, 0.675, 0.19)
        case .EaseOutCubic: return CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        case .EaseInOutCubic: return CAMediaTimingFunction(controlPoints: 0.645, 0.045, 0.355, 1)
        case .EaseInQuart: return CAMediaTimingFunction(controlPoints: 0.895, 0.03, 0.685, 0.22)
        case .EaseOutQuart: return CAMediaTimingFunction(controlPoints: 0.165, 0.84, 0.44, 1)
        case .EaseInOutQuart: return CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
        case .EaseInQuint: return CAMediaTimingFunction(controlPoints: 0.755, 0.05, 0.855, 0.06)
        case .EaseOutQuint: return CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        case .EaseInOutQuint: return CAMediaTimingFunction(controlPoints: 0.86, 0, 0.07, 1)
        case .EaseInExpo: return CAMediaTimingFunction(controlPoints: 0.95, 0.05, 0.795, 0.035)
        case .EaseOutExpo: return CAMediaTimingFunction(controlPoints: 0.19, 1, 0.22, 1)
        case .EaseInOutExpo: return CAMediaTimingFunction(controlPoints: 1, 0, 0, 1)
        case .EaseInCirc: return CAMediaTimingFunction(controlPoints: 0.6, 0.04, 0.98, 0.335)
        case .EaseOutCirc: return CAMediaTimingFunction(controlPoints: 0.075, 0.82, 0.165, 1)
        case .EaseInOutCirc: return CAMediaTimingFunction(controlPoints: 0.785, 0.135, 0.15, 0.86)
        case .EaseInBack: return CAMediaTimingFunction(controlPoints: 0.6, -0.28, 0.735, 0.045)
        case .EaseOutBack: return CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.275)
        case .EaseInOutBack: return CAMediaTimingFunction(controlPoints: 0.68, -0.55, 0.265, 1.55)
        }
    }
    
    func getAnimationOptions(curve: SpringAnimationCurve) -> UIView.AnimationOptions {
        switch curve {
        case .EaseIn: return .curveEaseIn
        case .EaseOut: return .curveEaseOut
        case .EaseInOut: return .curveEaseInOut
        default: return .curveLinear
        }
    }
    
    public func animate() {
        animateFrom = true
        animatePreset()
        setView {}
    }
    
    public func animateNext(completion: @escaping () -> ()) {
        animateFrom = true
        animatePreset()
        setView {
            completion()
        }
    }
    
    public func animateTo() {
        animateFrom = false
        animatePreset()
        setView {}
    }
    
    public func animateToNext(completion: @escaping () -> ()) {
        animateFrom = false
        animatePreset()
        setView {
            completion()
        }
    }
        
    func setView(completion: @escaping () -> ()) {
        if animateFrom {
            let translate = CGAffineTransform(translationX: self.x, y: self.y)
            let scale = CGAffineTransform(scaleX: self.scaleX, y: self.scaleY)
            let rotate = CGAffineTransform(rotationAngle: self.rotate)
            let translateAndScale = translate.concatenating(scale)
            self.transform = rotate.concatenating(translateAndScale)
            
            self.alpha = self.opacity
        }
        
        UIView.animate(
            withDuration: TimeInterval(duration),
            delay: TimeInterval(delay),
            usingSpringWithDamping: damping,
            initialSpringVelocity: velocity,
            options: [getAnimationOptions(curve: self.curve), .allowUserInteraction],
            animations: {
                if self.animateFrom {
                    self.transform = CGAffineTransform.identity
                    self.alpha = 1
                } else {
                    let translate = CGAffineTransform(translationX: self.x, y: self.y)
                    let scale = CGAffineTransform(scaleX: self.scaleX, y: self.scaleY)
                    let rotate = CGAffineTransform(rotationAngle: self.rotate)
                    let translateAndScale = translate.concatenating(scale)
                    self.transform = rotate.concatenating(translateAndScale)
                    
                    self.alpha = self.opacity
                }
                
            }, completion: { _ in
                completion()
                self.resetAll()
            }
        )
    }
    
    func reset() {
        x = 0
        y = 0
        opacity = 1
    }
    
    func resetAll() {
        x = 0
        y = 0
        animation = .Flash
        opacity = 1
        scaleX = 1
        scaleY = 1
        rotate = 0
        damping = 0.7
        velocity = 0.7
        repeatCount = 1
        delay = 0
        duration = 0.7
    }
}
