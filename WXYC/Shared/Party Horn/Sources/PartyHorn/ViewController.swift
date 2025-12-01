//
//  ViewController.swift
//  Party Horn
//
//  Created by Jake Bromberg on 8/11/25.
//

import UIKit
import Vortex
import SwiftUI

class ViewController: UIViewController {
    @IBOutlet weak var partyHorn: PartyHornView!

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.partyHorn.zoomInPartyHorn()
    }
}
