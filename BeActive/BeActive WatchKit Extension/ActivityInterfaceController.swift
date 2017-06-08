//
//  ActivityInterfaceController.swift
//  BeActive
//
//  Created by Konstantin Khokhlov on 08.06.17.
//  Copyright © 2017 Konstantin Khokhlov. All rights reserved.
//

import WatchKit
import Foundation
import HealthKit

class ActivityInterfaceController: WKInterfaceController {

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        guard let currentActivity = context as? (name: String, type: HKWorkoutActivityType) else { return }
        setTitle(currentActivity.name)
    }
}
