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
//        let playButton = CPNowPlayingImageButton(image: UIImage.checkmark, handler: { button in
//            RadioPlayerController.shared.toggle()
//        })
//
//        template.updateNowPlayingButtons([playButton])
//        NowPlayingService.shared.observe { nowPlayingItem in
//            template.up
//        }
        
        interfaceController.setRootTemplate(template, animated: true)
//        interfaceController.pushTemplate(template, animated: false)
    }
}
