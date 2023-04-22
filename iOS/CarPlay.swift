//
//  CarPlay.swift
//  WXYC
//
//  Created by Jake Bromberg on 1/7/23.
//  Copyright © 2023 WXYC. All rights reserved.
//

import Foundation
import CarPlay
import Core

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    // CarPlay connected
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let template = CPNowPlayingTemplate.shared
        interfaceController.setRootTemplate(template, animated: true, completion: nil)
    }
}
