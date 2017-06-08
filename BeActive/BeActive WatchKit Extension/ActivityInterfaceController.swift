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

class ActivityInterfaceController: WKInterfaceController, HKWorkoutSessionDelegate {

    // MARK: - Outlets
    @IBOutlet private var heartRateLabel: WKInterfaceLabel!
    @IBOutlet private var pauseButton: WKInterfaceButton!
    @IBOutlet private var continueButton: WKInterfaceButton!
    @IBOutlet private var endButton: WKInterfaceButton!

    // MARK: - Properties
    private var currentActivity = (name: "Cycling", type: HKWorkoutActivityType.cycling) {
        didSet {
            setTitle(currentActivity.name)
        }
    }
    private let healthStore = HKHealthStore()
    private var startDate = Date()
    private var activeDataQueries = [HKQuery]()
    private var activitySession: HKWorkoutSession?

    private var currentHeartRate = 0.0 {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.heartRateLabel.setText(self?.currentHeartRate.description)
            }
        }
    }

    // MARK: - WKInterfaceController
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        guard let activity = context as? (name: String, type: HKWorkoutActivityType) else { return }
        currentActivity = activity

        requestAutorization(in: healthStore)
    }

    /// End the session and stops queries before removing the interface controller.
    override func willDisappear() {
        super.willDisappear()

        guard let session = activitySession else { return }
        healthStore.end(session)
        for query in activeDataQueries {
            healthStore.stop(query)
        }
        activeDataQueries.removeAll()
    }

    // MARK: - HealthKit
    /// Requests permission to save and read the specified data types.
    ///
    /// - Parameter healthStore: HealthStore object.
    private func requestAutorization(in healthStore: HKHealthStore) {

        let savedTypes: Set<HKSampleType> = [HKSampleType.quantityType(forIdentifier: .heartRate)!]
        let readedTypes: Set<HKObjectType> = [HKObjectType.quantityType(forIdentifier: .heartRate)!]

        healthStore.requestAuthorization(toShare: savedTypes, read: readedTypes, completion: { [weak self] (success, _) in
            if success {
                self?.startSession(for: (self?.currentActivity.type)!)
            }
        })
    }

    /// Starts executing the provided query.
    ///
    /// - Parameter quantityTypeIdentifier: The provided query.
    private func startQuery(for quantityTypeIdentifier: HKQuantityTypeIdentifier) {

        /// The predicate that matches all the objects that were created by the curent device.
        let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])

        /// The predicate for objects after the startDate.
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)

        /// The compound predicate.
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [devicePredicate, datePredicate])

        let updateHanler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            [weak self] (query, samples, deletedObjects, queryAnchor, error) in
            guard let samples = samples as? [HKQuantitySample] else { return }
            guard let heartRate = samples.last?.quantity.doubleValue(for: HKUnit(from: "count/min")) else { return }
            self?.currentHeartRate = heartRate
        }

        let query = HKAnchoredObjectQuery(
            type: HKSampleType.quantityType(forIdentifier: quantityTypeIdentifier)!,
            predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: updateHanler)

        query.updateHandler = updateHanler

        healthStore.execute(query)
        activeDataQueries.append(query)
    }

    /// Start queries
    private func startQueries() {
        startQuery(for: .heartRate)
        WKInterfaceDevice.current().play(.start)
    }

    /// Starts a workout session for an activity type.
    ///
    /// - Parameter type: An activity type.
    private func startSession(for type: HKWorkoutActivityType) {
        let config = HKWorkoutConfiguration()
        config.activityType = type
        config.locationType = .outdoor

        guard let session = try? HKWorkoutSession(configuration: config) else { return }
        activitySession = session
        healthStore.start(session)
        startDate = Date()
        session.delegate = self
    }

    // MARK: - Actions
    /// Pauses the session.
    @IBAction private func pauseButtonPressed() {
        guard let session = activitySession else { return }
        pauseButton.setHidden(true)
        continueButton.setHidden(false)
        endButton.setHidden(false)
        healthStore.pause(session)
    }

    /// Resumes the session.
    @IBAction private func continueButtonPressed() {
        guard let session = activitySession else { return }
        pauseButton.setHidden(false)
        continueButton.setHidden(true)
        endButton.setHidden(false)
        healthStore.resumeWorkoutSession(session)
    }

    /// Pops the interface controller
    @IBAction private func endButtonPressed() {
        pop()
    }

    // MARK: - HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        startQueries()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session fails - \(error)")
    }
}
