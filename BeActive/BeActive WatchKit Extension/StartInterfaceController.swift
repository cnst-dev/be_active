//
//  StartInterfaceController.swift
//  BeActive
//
//  Created by Konstantin Khokhlov on 07.06.17.
//  Copyright © 2017 Konstantin Khokhlov. All rights reserved.
//

import WatchKit
import Foundation
import HealthKit

class StartInterfaceController: WKInterfaceController {

    // MARK: - Outlets
    @IBOutlet private var activityPicker: WKInterfacePicker!

    // MARK: - Properties
    private let activities = [
        MovementActivity(name: "Swimming", type: .swimming, distanceType: .distanceSwimming),
        MovementActivity(name: "Cycling", type: .cycling, distanceType: .distanceCycling),
        MovementActivity(name: "Running", type: .running, distanceType: .distanceWalkingRunning)
    ]

    private var currentActivity = MovementActivity(name: "Swimming", type: .swimming, distanceType: .distanceSwimming)

    // MARK: - WKInterfaceController
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        activityPicker.setItems(makePickerItems(from: activities))
    }

    // MARK: - Methods
    /// Makes a picker items array from an activity dictionary.
    ///
    /// - Parameter dictionary: An activity dictionary.
    /// - Returns: A picker items array.
    private func makePickerItems(from activities: [MovementActivity]) -> [WKPickerItem] {
        var activityItems = [WKPickerItem]()

        for activity in activities {
            let item = WKPickerItem()
            item.title = activity.name
            activityItems.append(item)
        }
        return activityItems
    }

    // MARK: - Actions
    /// Sets the current activity.
    ///
    /// - Parameter value: A value of the selected line.
    @IBAction private func activityPickerChanged(_ value: Int) {
        currentActivity = activities[value]
    }

    /// Pushes the ActivityInterfaceController onto the scene.
    @IBAction private func startButtonPressed() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        pushController(withName: "Activity", context: currentActivity)
    }
}
