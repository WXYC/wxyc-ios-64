//
//  CarPlaySceneDelegate.swift
//  WXYC
//
//  Created by Jake Bromberg on 1/17/22.
//  Copyright © 2022 WXYC. All rights reserved.
//

import Foundation
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    // CarPlay connected
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
//        let listTemplate = CPNowPlayingTemplate.shared
        interfaceController.setRootTemplate(CPNowPlayingTemplate.shared, animated: true) { success, error in
            print("success: \(success), error: \(error)")
        }
    }
    // CarPlay disconnected
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
    
    
    
//    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController, from window: CPWindow)

}
