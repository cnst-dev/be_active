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

    // MARK: - Nested
    enum HUDTypes: String {
        case heartRate = "BEATS/MINUTE", energy = "Kilocalories"
    }

    // MARK: - Outlets
    @IBOutlet private var valueLabel: WKInterfaceLabel!
    @IBOutlet var unitLabel: WKInterfaceLabel!
    @IBOutlet private var pauseButton: WKInterfaceButton!
    @IBOutlet private var continueButton: WKInterfaceButton!
    @IBOutlet private var endButton: WKInterfaceButton!
    @IBOutlet private var timer: WKInterfaceTimer!

    // MARK: - Properties
    private var currentActivity = (name: "Cycling", type: HKWorkoutActivityType.cycling) {
        didSet {
            setTitle(currentActivity.name)
        }
    }

    private var currentHUDType = HUDTypes.heartRate
    private let healthStore = HKHealthStore()
    private var startDate = Date()
    private var pauseDate = Date()
    private var pausesIntervals = TimeInterval(floatLiteral: 0.0)
    private var endDate = Date()
    private var activeDataQueries = [HKQuery]()
    private var currentSession: HKWorkoutSession?
    private var isSessionActive: Bool {
        return currentSession?.state == HKWorkoutSessionState.running
    }

    private var currentHeartRate = 0.0 {
        didSet {
            print("Heart rate \(currentHeartRate)")
            guard currentHUDType == .heartRate else { return }
            DispatchQueue.main.async { [weak self] in
                self?.valueLabel.setText(self?.currentHeartRate.description)
            }
        }
    }

    var totalEnergyBurned = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: 0.0) {
        didSet {
            print("Energy burned: \(totalEnergyBurned)")
            guard currentHUDType == .energy else { return }
            DispatchQueue.main.async { [weak self] in
                guard let energy = self?.totalEnergyBurned.doubleValue(for: HKUnit.kilocalorie()) else { return }
                self?.valueLabel.setText(String(format: "%.0f", energy))
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

        guard let session = currentSession else { return }
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

        let typesToSave: Set<HKSampleType> = [
            .workoutType(),
            HKSampleType.quantityType(forIdentifier: .heartRate)!,
            HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!]
        let typesToRead: Set<HKObjectType> = [
            .activitySummaryType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: typesToSave, read: typesToRead, completion: { [weak self] (success, _) in
            if success {
                self?.startSession(for: (self?.currentActivity.type)!)
            }
        })
    }

    /// Starts executing the provided query for a quantity sample type.
    ///
    /// - Parameter quantityTypeIdentifier: A quantity sample type.
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
            self?.process(samples: samples, for: quantityTypeIdentifier)
        }

        let query = HKAnchoredObjectQuery(
            type: HKSampleType.quantityType(forIdentifier: quantityTypeIdentifier)!,
            predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: updateHanler)

        query.updateHandler = updateHanler

        healthStore.execute(query)
        activeDataQueries.append(query)
    }

    /// Start queries.
    private func startQueries() {
        startQuery(for: .heartRate)
        startQuery(for: .activeEnergyBurned)
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
        currentSession = session
        healthStore.start(session)
        startDate = Date()
        session.delegate = self
        timer.setDate(startDate)
        timer.start()
    }

    /// Saves a workout session.
    ///
    /// - Parameter session: A workout session.
    private func saveSession(_ session: HKWorkoutSession) {
        let config = session.workoutConfiguration

        let workout = HKWorkout(activityType: config.activityType, start: startDate, end: endDate,
                                workoutEvents: nil, totalEnergyBurned: totalEnergyBurned, totalDistance: nil,
                                metadata: [HKMetadataKeyIndoorWorkout: false])
        healthStore.save(workout) { [weak self] (success, _) in
            if success {
                self?.pop()
            }
        }

    }

    /// Passes data from samples to properties.
    ///
    /// - Parameters:
    ///   - samples: Data samples.
    ///   - quantityTypeIdentifier: A quantity sample type.
    func process(samples: [HKQuantitySample], for quantityTypeIdentifier: HKQuantityTypeIdentifier) {

        guard isSessionActive else { return }

        for sample in samples {
            switch quantityTypeIdentifier {
            case HKQuantityTypeIdentifier.heartRate:
                currentHeartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            case HKQuantityTypeIdentifier.activeEnergyBurned:
                let newEnergy = sample.quantity.doubleValue(for: HKUnit(from: .kilocalorie))
                let currentEnergy = totalEnergyBurned.doubleValue(for: HKUnit(from: .kilocalorie))
                totalEnergyBurned = HKQuantity(unit: HKUnit(from: .kilocalorie), doubleValue: currentEnergy + newEnergy)
            default:
                break
            }
        }
    }

    // MARK: - Actions
    /// Sets the current HUD type.
    @IBAction private func interfaceButtonPressed() {
        switch currentHUDType {
        case .heartRate:
            currentHUDType = .energy
            let energy = totalEnergyBurned.doubleValue(for: HKUnit.kilocalorie())
            valueLabel.setText(String(format: "%.0f", energy))
            unitLabel.setText(currentHUDType.rawValue)
        case .energy:
            currentHUDType = .heartRate
            valueLabel.setText(currentHeartRate.description)
            unitLabel.setText(currentHUDType.rawValue)
        }
    }

    /// Pauses the session.
    @IBAction private func pauseButtonPressed() {
        guard let session = currentSession else { return }
        pauseButton.setHidden(true)
        continueButton.setHidden(false)
        endButton.setHidden(false)
        healthStore.pause(session)
        timer.stop()
        pauseDate = Date()
    }

    /// Resumes the session.
    @IBAction private func continueButtonPressed() {
        guard let session = currentSession else { return }
        pauseButton.setHidden(false)
        continueButton.setHidden(true)
        endButton.setHidden(false)
        healthStore.resumeWorkoutSession(session)
        pausesIntervals += pauseDate.timeIntervalSinceNow
        let interval = startDate.timeIntervalSinceNow - pausesIntervals
        timer.setDate(Date(timeIntervalSinceNow: interval))
        timer.start()
    }

    /// Pops the interface controller.
    @IBAction private func endButtonPressed() {
        guard let session = currentSession else { return }
        endDate = Date()
        saveSession(session)
    }

    // MARK: - HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .running && fromState == .notStarted else { return }
        startQueries()
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session fails - \(error)")
    }
}
