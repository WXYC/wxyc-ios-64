//
//  PlaycutActivityItem.swift
//  WXYC
//
//  Created by Jake Bromberg on 3/19/19.
//  Copyright © 2019 WXYC. All rights reserved.
//

import UIKit
import Core

nonisolated extension UIActivity.ActivityType {
  static let wxyc = UIActivity.ActivityType("org.wxyc")
}

nonisolated final class PlaycutActivityItem: UIActivity {
  let playcut: Playcut
  var image: UIImage?
  
  init(playcut: Playcut) {
    self.playcut = playcut
      self.image = #imageLiteral(resourceName: "logo.pdf")
  }
  
  override class var activityCategory: UIActivity.Category {
    return .share
  }
  
  override var activityType: UIActivity.ActivityType? {
    return .wxyc
  }
  
  override var activityImage: UIImage? {
    return self.image
  }
  
  override var activityTitle: String? {
    return "\(self.playcut.songTitle) by \(self.playcut.artistName)"
  }
  
  override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
    for case is UIImage in activityItems {
      return true
    }
    
    return false
  }
}
