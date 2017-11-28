import UIKit
import Foundation

@IBDesignable
final class PlayPauseView: UIView {
    enum State {
        case play, pause
    }

    fileprivate var state: State = .pause
    
    lazy var playLayer: CAShapeLayer = {
        let playLayer = CAShapeLayer()
        playLayer.fillColor = UIColor.white.cgColor
        return playLayer
    }()

    lazy var pauseLayer: CAShapeLayer = {
        let pauseLayer = CAShapeLayer()
        pauseLayer.fillColor = UIColor.white.cgColor
        return pauseLayer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        sharedInitialization()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        sharedInitialization()
    }

    func sharedInitialization() {
        clipsToBounds = true
        layer.addSublayer(playLayer)
        layer.addSublayer(pauseLayer)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        playLayer.frame = bounds
        playLayer.path = playAnimationValues.toValue

        pauseLayer.frame = bounds
        let beziers = Beziers(frame: bounds)
        pauseLayer.path = beziers.pause.cgPath
        pauseLayer.position.x = pauseAnimationValues.toValue
    }

    struct Beziers {
        var playPart1: UIBezierPath
        var playPart2: UIBezierPath
        var pause: UIBezierPath

        init(frame: CGRect) {
            func fastFloor(_ x: CGFloat) -> CGFloat { return floor(x) }

            playPart1 = UIBezierPath()
            playPart1.move(to: CGPoint(x: frame.minX + frame.width / 3.0, y: frame.minY))
            playPart1.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
            playPart1.addLine(to: CGPoint(x: frame.minX, y: frame.minY + frame.height))
            playPart1.addLine(to: CGPoint(x: frame.minX + frame.width / 3.0, y: frame.minY + frame.height))

            playPart2 = UIBezierPath()
            playPart2.move(to: CGPoint(x: frame.minX + frame.width, y: frame.minY + frame.height / 2.0))
            playPart2.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
            playPart2.addLine(to: CGPoint(x: frame.minX, y: frame.minY + frame.height))
            playPart2.addLine(to: CGPoint(x: frame.minX, y: frame.minY + frame.height))

            pause = UIBezierPath()
            pause.move(to: CGPoint(x: frame.minX + frame.width, y: frame.minY))
            pause.addLine(to: CGPoint(x: frame.minX + (2.0 / 3.0) * frame.width, y: frame.minY))
            pause.addLine(to: CGPoint(x: frame.minX + (2.0 / 3.0) * frame.width, y: frame.minY + frame.height))
            pause.addLine(to: CGPoint(x: frame.minX + frame.width, y: frame.minY + frame.height))
        }
    }

    var playAnimationValues: (fromValue: CGPath, toValue: CGPath) {
        let playPart1 = Beziers(frame: bounds).playPart1.cgPath
        let playPart2 = Beziers(frame: bounds).playPart2.cgPath

        return state == .pause ? (playPart1, playPart2) : (playPart2, playPart1)
    }

    var pauseAnimationValues: (fromValue: CGFloat, toValue: CGFloat) {
        let value1 = bounds.midX
        let value2 = -(2.0 / 3.0) * bounds.width

        return state == .pause ? (value1, value2) : (value2, value1)
    }

    func animate() {
        let playDuration: Double = state == .play ? 0.45 : 0.45
        let playBeginTime: Double = state == .play ? 0.2 : 0
        let playTimingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.2, 0.1, 1)

        let pauseDuration: Double = state == .play ? 0.25 : 0.35
        let pauseBeginTime: Double = state == .play ? 0 : 0
        let pauseTimingFunction = state == .play ?
            CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn) : CAMediaTimingFunction(controlPoints: 0.1, 0.2, 0.1, 1)

        state = state == .play ? .pause : .play

        let playAnimationGroup = CAAnimationGroup()
        playAnimationGroup.timingFunction = playTimingFunction
        playAnimationGroup.duration = playDuration
        playAnimationGroup.beginTime = CACurrentMediaTime() + playBeginTime
        playAnimationGroup.fillMode = kCAFillModeForwards
        playAnimationGroup.isRemovedOnCompletion = false

        let animatePlayPath = CABasicAnimation(keyPath: "path")
        animatePlayPath.fromValue = playAnimationValues.fromValue
        animatePlayPath.toValue = playAnimationValues.toValue

        playAnimationGroup.animations = [animatePlayPath]
        playLayer.add(playAnimationGroup, forKey: nil)

        let pauseAnimationGroup = CAAnimationGroup()
        pauseAnimationGroup.timingFunction = pauseTimingFunction
        pauseAnimationGroup.duration = pauseDuration
        pauseAnimationGroup.beginTime = CACurrentMediaTime() + pauseBeginTime
        pauseAnimationGroup.fillMode = kCAFillModeForwards
        pauseAnimationGroup.isRemovedOnCompletion = false

        let animatePausePositionX = CABasicAnimation(keyPath: "position.x")
        animatePausePositionX.fromValue = pauseAnimationValues.fromValue
        animatePausePositionX.toValue = pauseAnimationValues.toValue

        pauseAnimationGroup.animations = [animatePausePositionX]
        pauseLayer.add(pauseAnimationGroup, forKey: nil)
    }
}
