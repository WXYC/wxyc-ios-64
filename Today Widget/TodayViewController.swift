//
//  TodayViewController.swift
//  Today Widget
//
//  Created by Jake Bromberg on 11/26/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import UIKit
import NotificationCenter
import UI
import Core
import Spring

class TodayViewController: UIViewController, NowPlayingPresentable, PlaylistServiceObserver {
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var albumImageView: UIImageView!

    @IBOutlet weak var containerStackView: UIStackView!
    @IBOutlet weak var labelsStackView: UIStackView!

    var playlistService: PlaylistService?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let context = self.extensionContext {
            // TODO: 🐛🔨. I'm commenting this out for now because there's a sizing issue in the expanded mode.
            // We consistently report a height too high for our content. I played around with some layout code, but
            // never got to the bottom of this. Anyway, the widget is a bit ungainly in the expanded layout.
            // context.widgetLargestAvailableDisplayMode = .expanded

            self.containerStackView.axis = self.containerAxis(forDisplayMode: context.widgetActiveDisplayMode)
            self.labelsStackView.alignment = self.labelAlignment(forDisplayMode: context.widgetActiveDisplayMode)
            self.preferredContentSize = self.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
        }

        self.playlistService = PlaylistService(observers: self)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If the user taps on the today widget, open the app.
        let url = URL(string: "wxyc://")!
        self.extensionContext?.open(url, completionHandler: nil)
    }
}

extension TodayViewController: NCWidgetProviding {
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        completionHandler(NCUpdateResult.newData)
    }
    
    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        self.containerStackView.axis = self.containerAxis(forDisplayMode: activeDisplayMode)
        self.labelsStackView.alignment = self.labelAlignment(forDisplayMode: activeDisplayMode)
        
        self.preferredContentSize = self.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .fittingSizeLevel)
    }
    
    private func containerAxis(forDisplayMode displayMode: NCWidgetDisplayMode) -> NSLayoutConstraint.Axis {
        switch displayMode {
        case .compact:
            return .horizontal
        case .expanded:
            return .vertical
        }
    }
    
    private func labelAlignment(forDisplayMode displayMode: NCWidgetDisplayMode) -> UIStackView.Alignment {
        switch displayMode {
        case .compact:
            return .leading
        case .expanded:
            return .center
        }
    }
}
