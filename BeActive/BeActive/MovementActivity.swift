//
//  MovementActivity.swift
//  BeActive
//
//  Created by Konstantin Khokhlov on 13.06.17.
//  Copyright © 2017 Konstantin Khokhlov. All rights reserved.
//

import Foundation
import HealthKit

struct MovementActivity {
    var name: String
    var type: HKWorkoutActivityType
    var distanceType: HKQuantityTypeIdentifier
}
