//
//  PartyHornView.swift
//  Party Horn
//
//  Created by Jake Bromberg on 8/16/25.
//

import Foundation
import UIKit
import SwiftUI
import os

public final class PartyHornView: UIView, UIGestureRecognizerDelegate {
    private let soundPlayer = SoundPlayer()
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let haptics = Haptics()
    private let logger = Logger(subsystem: "com.jakebromberg.partyhorn", category: "PartyHornView")
    
    // Composed UIImageView
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    public init() {
        super.init(frame: .zero)
        
        setUpImageView()
        isUserInteractionEnabled = true
        impact.prepare()
        setUpTapGestureRecognizer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setUpImageView()
        isUserInteractionEnabled = true
        impact.prepare()
        setUpTapGestureRecognizer()
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        // Ensure image from storyboard is set on the composed imageView
        // The image property setter will handle forwarding to imageView
    }
    
    private func setUpImageView() {
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.75),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.6),
        ])
    }
    
    // Forward UIImageView properties
    public var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }
    
    public override var contentMode: UIView.ContentMode {
        get { imageView.contentMode }
        set { imageView.contentMode = newValue }
    }
    
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        guard let superview else {
            return
        }
        // Ensure neither this view nor its ancestors clip during transforms
        clipsToBounds = false
        layer.masksToBounds = false
        superview.clipsToBounds = false
        superview.layer.masksToBounds = false

        superview.addSubview(confettiHost.view)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: confettiHost.view.leadingAnchor),
            trailingAnchor.constraint(equalTo: confettiHost.view.trailingAnchor),
            confettiHost.view.topAnchor.constraint(equalTo: superview.topAnchor),
            confettiHost.view.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
        ])
        
        superview.addSubview(inversionView)
        inversionView.isHidden = true
        inversionView.backgroundColor = .white
        inversionView.isUserInteractionEnabled = false
        inversionView.layer.compositingFilter = "differenceBlendMode"
        inversionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inversionView.leadingAnchor.constraint(equalTo: confettiHost.view.leadingAnchor),
            inversionView.trailingAnchor.constraint(equalTo: confettiHost.view.trailingAnchor),
            confettiHost.view.topAnchor.constraint(equalTo: inversionView.topAnchor),
            confettiHost.view.bottomAnchor.constraint(equalTo: inversionView.bottomAnchor),
        ])
    }
    
    func setUpTapGestureRecognizer() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.01
        press.allowableMovement = 0.0
//        press.cancelsTouchesInView = true
        press.delegate = self
        addGestureRecognizer(press)
    }
    
    @objc private func handlePress(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            guard tapIsInSafeArea(gr.location(in: superview)) else { return }
            
            imageView.contentMode = .center
            enqueueTimestamp()
            soundPlayer.play()
            impact.impactOccurred()
            shake()
            
            if shouldEnergize() {
                inversionTimer.start()
                burst()
                rumble()
            } else {
                inversionTimer.stop()
            }
        case .ended, .cancelled, .failed:
            imageView.contentMode = .scaleAspectFit
        default:
            break
        }
    }
    
    func tapIsInSafeArea(_ tapLocation: CGPoint) -> Bool {
        let superview = superview!
        let insets = superview.safeAreaInsets
        let safeFrame = superview.bounds.inset(by: insets)
        
        return safeFrame.contains(tapLocation)
    }
    
    // MARK: Inversion
    
    enum InversionStyle {
        case normal
        case inverted
    }
    
    private let inversionFilter: CIFilter? = CIFilter(name: "CIColorInvert")
    private let inversionView: UIView = .init()
    private var inversionStyle: InversionStyle = .normal
    private lazy var inversionTimer = RepeatingTimer(initialDelay: 2, interval: 0.5) {
        let timeInterval = Date.now.timeIntervalSinceReferenceDate - self.lastTimeInterval
        if timeInterval < 1 {
            print("inversion timer should energize")
            self.invert()
        } else if self.inversionStyle == .inverted {
            print("inversion timer WON'T energize")
            self.invert()
        }
    }
    
    private func invert() {
        switch inversionStyle {
        case .normal:
            inversionStyle = .inverted
            inversionView.isHidden = false
            log("inverted")
        case .inverted:
            inversionStyle = .normal
            inversionView.isHidden = true
            log("normal")
        }
    }
    
    // MARK: Zoom
    
    @IBOutlet weak var partyHornWidthConstraint: NSLayoutConstraint?
    
    func zoomInPartyHorn() {
        imageView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        partyHornWidthConstraint?.priority = .defaultLow
        
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.25,
            initialSpringVelocity: 0.8,
            options: [.curveEaseInOut],
            animations: {
                self.alpha = 1.0
                self.imageView.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.superview?.layoutIfNeeded()
            },
            completion: nil
        )
    }
    
    // MARK: - Energizing
    
    static let threshold: TimeInterval = 0.25

    var lastTimeInterval: TimeInterval = 0
    var queue: Queue<TimeInterval> = .init(capacity: 5)

    func enqueueTimestamp() {
        let now = Date.now.timeIntervalSinceReferenceDate
        let timeInterval = now - lastTimeInterval
        lastTimeInterval = now
        queue.enqueue(timeInterval)
    }
    
    func shouldEnergize() -> Bool {
        print("average \(queue.average())")
        return queue.average() < Self.threshold
    }
    
    // MARK: Confetti

    private var confettiHost: UIHostingController<ConfettiView> =  {
        let swiftUIView = ConfettiView()
        let confettiHost = UIHostingController(rootView: swiftUIView)
        confettiHost.view.backgroundColor = .clear
        confettiHost.view.isUserInteractionEnabled = false
        confettiHost.view.clipsToBounds = false
        confettiHost.view.translatesAutoresizingMaskIntoConstraints = false
        
        return confettiHost
    }()

    func burst() {
        let x = Int.random(in: 0..<Int(bounds.width))
        let y = Int.random(in: 0..<Int(bounds.height))
        let location = CGPoint(x: x, y: y)
        confettiHost.rootView.trigger.fire(with: location)
    }
    
    // MARK: Haptics
    
    func rumble() {
        haptics.onTap()
    }
    
    // MARK: Party horn shake
    
    var shakeAnimator: UIViewPropertyAnimator = {
        let params = UISpringTimingParameters(
            mass: 0.125,
            stiffness: 720,
            damping: 3,
            initialVelocity: .init(dx: 10, dy: 0)
        )

        return UIViewPropertyAnimator(duration: 0, timingParameters: params)
    }()

    func shake() {
        interruptShake()
        
        imageView.transform = CGAffineTransform(rotationAngle: .pi / 8)

        shakeAnimator.addAnimations {
            self.imageView.transform = .identity
        }
        shakeAnimator.startAnimation()
    }

    func interruptShake() {
        shakeAnimator.stopAnimation(true)  // true = jump to current position without completing
        shakeAnimator.finishAnimation(at: .current) // leave it where it is
    }
    
    // MARK: - Logging
    
    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[\(formatter.string(from: Date()))] \(message)")
    }
}

// MARK: - SwiftUI Bridge

@available(iOS 13.0, *)
public struct PartyHornSwiftUIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var partyHornView: PartyHornView?
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("layer 0 background", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                
                Image("layer 1 swizzles", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .wipe(direction: .bottomToTop)
                
                Image("layer 2 swizzles", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .wipe(direction: .topToBottom)

                PartyHornViewRepresentable { view in
                    partyHornView = view
                    partyHornView?.alpha = 0.0
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        partyHornView?.zoomInPartyHorn()
                    }
                }
                
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .padding(.top, geometry.safeAreaInsets.top + 64)

            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    PartyHornSwiftUIView()
}

@available(iOS 13.0, *)
private struct PartyHornViewRepresentable: UIViewRepresentable {
    var onViewReady: ((PartyHornView) -> Void)?
    
    func makeUIView(context: Context) -> PartyHornView {
        let view = PartyHornView()
        // Set the default image from the package bundle
        if let image = UIImage(named: "party horn", in: .module, compatibleWith: nil) {
            view.image = image
        }
        context.coordinator.view = view
        // Notify when view is ready
        DispatchQueue.main.async {
            onViewReady?(view)
        }
        return view
    }
    
    func updateUIView(_ uiView: PartyHornView, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    final class Coordinator {
        var view: PartyHornView?
    }
}
