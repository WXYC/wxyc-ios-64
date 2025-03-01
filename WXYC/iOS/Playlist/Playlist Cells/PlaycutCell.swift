//
//  PlaycutCell.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/5/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import UIKit

@MainActor
protocol PlaycutShareDelegate: AnyObject {
    func presentShareSheet(for activity: PlaycutActivityItem, from view: UIView)
}

@objc(PlaycutCell)
final class PlaycutCell: UITableViewCell & Sendable {
    @IBOutlet var artworkImageView: UIImageView!
    @IBOutlet var artistLabel: UILabel!
    @IBOutlet var songLabel: UILabel!
    @IBOutlet var actionButton: UIButton!
    @IBOutlet var containerView: UIVisualEffectView!
    
    var activity: PlaycutActivityItem?
    weak var delegate: PlaycutShareDelegate? = nil
    
    // MARK: Configuration
    
    func configure(with image: UIImage, token: UInt64) {
        guard token == self.token else {
            return
        }
        
        DispatchQueue.main.async {
            UIView.transition(
                with: self.artworkImageView,
                duration: 0.25,
                options: [.transitionCrossDissolve],
                animations: { self.artworkImageView.image = image },
                completion: nil
            )
        }
    }
    
    var token: UInt64?
    
    // MARK: Overrides
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        self.containerView.layer.cornerRadius = 6.0
        self.containerView.layer.masksToBounds = true
    }
    
    override func prepareForReuse() {
        self.artworkImageView.image = nil
        self.token = nil
    }
    
    // MARK: Private
    
    @objc @IBAction private func displayShareSheet() {
        // TODO: We should be referencing the view models here
        guard let activity = self.activity else {
            return
        }
        
        self.delegate?.presentShareSheet(for: activity, from: self.actionButton)
    }
}
