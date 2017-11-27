//
//  TodayViewController.swift
//  Today Widget
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import NotificationCenter

class TodayViewController: UIViewController, NCWidgetProviding {
    @IBOutlet weak var songLabel: UILabel!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var albumArtworkImageView: UIImageView!

    @IBOutlet weak var containerStackView: UIStackView!
    @IBOutlet weak var labelsStackView: UIStackView!

    let webservice = Webservice()

    override func viewDidLoad() {
        super.viewDidLoad()

        if let context = self.extensionContext {
            context.widgetLargestAvailableDisplayMode = .expanded

            self.containerStackView.axis = self.containerAxis(forDisplayMode: context.widgetActiveDisplayMode)
            self.labelsStackView.alignment = self.labelAlignment(forDisplayMode: context.widgetActiveDisplayMode)
            self.preferredContentSize = self.view.systemLayoutSizeFitting(UILayoutFittingCompressedSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
        }

        let playcutRequest = webservice.getCurrentPlaycut()
        playcutRequest.observe(with: self.updateWith(playcutResult:))

        let imageRequest = playcutRequest.getArtwork()
        imageRequest.observe(with: self.updateWith(artworkResult:))
    }
    
    func updateWith(playcutResult result: Result<Playcut>) {
        guard case let .success(playcut) = result else {
            return
        }

        DispatchQueue.main.async {
            self.songLabel.text = playcut.songTitle
            self.artistLabel.text = playcut.artistName
        }
    }
    
    func updateWith(artworkResult: Result<UIImage>) {
        DispatchQueue.main.async {
            UIView.transition(with: self.view, duration: 0.25, options: [.transitionCrossDissolve], animations: {
                if case let .success(artwork) = artworkResult {
                    self.albumArtworkImageView.image = artwork
                } else {
                    self.albumArtworkImageView.image = #imageLiteral(resourceName: "logo")
                }
            }, completion: nil)
        }
    }
    
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        completionHandler(NCUpdateResult.newData)
    }

    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        self.containerStackView.axis = self.containerAxis(forDisplayMode: activeDisplayMode)
        self.labelsStackView.alignment = self.labelAlignment(forDisplayMode: activeDisplayMode)

        self.preferredContentSize = self.view.systemLayoutSizeFitting(UILayoutFittingCompressedSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
//        print(maxSize)
//        print(self.view.systemLayoutSizeFitting(maxSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel))
    }

    func containerAxis(forDisplayMode displayMode: NCWidgetDisplayMode) -> UILayoutConstraintAxis {
        switch displayMode {
        case .compact:
            return .horizontal
        case .expanded:
            return .vertical
        }
    }

    func labelAlignment(forDisplayMode displayMode: NCWidgetDisplayMode) -> UIStackViewAlignment {
        switch displayMode {
        case .compact:
            return .leading
        case .expanded:
            return .center
        }
    }
}
