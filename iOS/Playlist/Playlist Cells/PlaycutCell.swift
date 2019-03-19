//
//  PlaycutCell.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/5/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import UIKit

@objc(PlaycutCell)
final class PlaycutCell: UITableViewCell {
    @IBOutlet var artworkImageView: UIImageView!
    @IBOutlet var artistLabel: UILabel!
    @IBOutlet var songLabel: UILabel!
    @IBOutlet var actionButton: UIButton!
    @IBOutlet var containerView: UIVisualEffectView!
    
    var activity: UIActivity?
    
    // MARK: Configuration
    
    func configure(with image: UIImage, token: Int) {
        guard token == self.token else {
            return
        }
        
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25, animations: {
                self.artworkImageView.image = image
            })
        }
    }
    
    var token: Int?
    
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
        
        let viewController = UIActivityViewController(activityItems: [self.artworkImageView.image ?? #imageLiteral(resourceName: "logo"), activity.activityTitle!, URL(string: "http://wxyc.org")!], applicationActivities: [activity])
        
        self.window?.rootViewController?.present(viewController, animated: true, completion: nil)
    }
}
