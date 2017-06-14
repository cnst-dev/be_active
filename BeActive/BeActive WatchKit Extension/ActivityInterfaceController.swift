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
    private enum HUDTypes: String {
        case heartRate = "BEATS/MINUTE", energy = "Kilocalories", distance = "Kilometers"
    }

    // MARK: - Outlets
    @IBOutlet private var valueLabel: WKInterfaceLabel!
    @IBOutlet private var unitLabel: WKInterfaceLabel!
    @IBOutlet private var pauseButton: WKInterfaceButton!
    @IBOutlet private var continueButton: WKInterfaceButton!
    @IBOutlet private var endButton: WKInterfaceButton!
    @IBOutlet private var timer: WKInterfaceTimer!

    // MARK: - Properties
    private var currentActivity = MovementActivity(name: "Swimming", type: .swimming, distanceType: .distanceSwimming) {
        didSet {
            setTitle(currentActivity.name)
        }
    }

    private var currentHUDType = HUDTypes.heartRate
    private let healthStore = HKHealthStore()
    private var startDate = Date()
    private var pauseDate = Date()
    private var pausesIntervals = TimeInterval(floatLiteral: 0.0)
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

    private var totalEnergyBurned = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: 0.0) {
        didSet {
            print("Energy burned: \(totalEnergyBurned)")
            guard currentHUDType == .energy else { return }
            DispatchQueue.main.async { [weak self] in
                guard let energy = self?.totalEnergyBurned.doubleValue(for: HKUnit.kilocalorie()) else { return }
                self?.valueLabel.setText(String(format: "%.0f", energy))
            }
        }
    }

    private var totalDistance = HKQuantity(unit: HKUnit.meter(), doubleValue: 0.0) {
        didSet {
            print("Total distance: \(totalDistance)")
            guard currentHUDType == .distance else { return }
            DispatchQueue.main.async { [weak self] in
                guard let meters = self?.totalDistance.doubleValue(for: HKUnit.meter()) else { return }
                self?.valueLabel.setText(String(format: "%.2f", meters / 1000))
            }
        }
    }

    // MARK: - WKInterfaceController
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        guard let activity = context as? MovementActivity else { return }
        currentActivity = activity

        requestAutorization(in: healthStore)
    }

    /// End the session and stops queries before removing the interface controller.
    override func willDisappear() {
        super.willDisappear()
        guard let session = currentSession else { return }
        saveSession(session)
        endSession(session)
    }

    // MARK: - HealthKit
    /// Requests permission to save and read the specified data types.
    ///
    /// - Parameter healthStore: HealthStore object.
    private func requestAutorization(in healthStore: HKHealthStore) {

        let typesToSave: Set<HKSampleType> = [
            .workoutType(),
            HKSampleType.quantityType(forIdentifier: .heartRate)!,
            HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKSampleType.quantityType(forIdentifier: currentActivity.distanceType)!]

        let typesToRead: Set<HKObjectType> = [
            .activitySummaryType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: currentActivity.distanceType)!]

        healthStore.requestAuthorization(toShare: typesToSave, read: typesToRead, completion: { [weak self] (success, _) in
            if success {
                self?.startSession(for: (self?.currentActivity.type)!)
            }
        })
    }

    // MARK: Queries
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
        startQuery(for: currentActivity.distanceType)
        WKInterfaceDevice.current().play(.start)
    }

    // MARK: Session
    /// Starts a workout session for an activity type.
    ///
    /// - Parameter type: An activity type.
    private func startSession(for type: HKWorkoutActivityType) {
        let config = HKWorkoutConfiguration()
        config.activityType = type
        config.locationType = .outdoor
        config.swimmingLocationType = .unknown

        guard let session = try? HKWorkoutSession(configuration: config) else {
            let action = WKAlertAction(title: "OK", style: .default, handler: { [weak self] in
                self?.pop()
            })
            presentAlert(withTitle: "Ooops!", message: "\(currentActivity.name) session is not supported on this device.", preferredStyle: .alert, actions: [action])
            return
        }

        currentSession = session
        healthStore.start(currentSession!)
        startDate = Date()
        currentSession?.delegate = self
        timer.setDate(startDate)
        timer.start()
    }

    /// Saves a workout session.
    ///
    /// - Parameter session: A workout session.
    private func saveSession(_ session: HKWorkoutSession) {
        let config = session.workoutConfiguration

        let workout = HKWorkout(activityType: config.activityType, start: startDate, end: Date(),
                                workoutEvents: nil, totalEnergyBurned: totalEnergyBurned, totalDistance: totalDistance,
                                metadata: [HKMetadataKeyIndoorWorkout: false])
        healthStore.save(workout) { (_, _) in }
    }

    /// Ends a workout session.
    ///
    /// - Parameter session: A workout session.
    private func endSession(_ session: HKWorkoutSession) {
        healthStore.end(session)
        for query in activeDataQueries {
            healthStore.stop(query)
        }
        activeDataQueries.removeAll()
    }

    /// Passes data from samples to properties.
    ///
    /// - Parameters:
    ///   - samples: Data samples.
    ///   - quantityTypeIdentifier: A quantity sample type.
    private func process(samples: [HKQuantitySample], for quantityTypeIdentifier: HKQuantityTypeIdentifier) {

        guard isSessionActive else { return }

        for sample in samples {
            switch quantityTypeIdentifier {
            case HKQuantityTypeIdentifier.heartRate:
                currentHeartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            case HKQuantityTypeIdentifier.activeEnergyBurned:
                let newEnergy = sample.quantity.doubleValue(for: HKUnit(from: .kilocalorie))
                let currentEnergy = totalEnergyBurned.doubleValue(for: HKUnit(from: .kilocalorie))
                totalEnergyBurned = HKQuantity(unit: HKUnit(from: .kilocalorie), doubleValue: currentEnergy + newEnergy)
            case currentActivity.distanceType:
                let newDistance = sample.quantity.doubleValue(for: HKUnit(from: .meter))
                let currentDistance = totalDistance.doubleValue(for: HKUnit(from: .meter))
                totalDistance = HKQuantity(unit: HKUnit(from: .meter), doubleValue: newDistance + currentDistance)
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
            currentHUDType = .distance
            let meters = totalDistance.doubleValue(for: HKUnit.meter())
            valueLabel.setText(String(format: "%.2f", meters / 1000))
            unitLabel.setText(currentHUDType.rawValue)
        case .distance:
            currentHUDType = .heartRate
            valueLabel.setText(currentHeartRate.description)
            unitLabel.setText(currentHUDType.rawValue)
        }
    }

    /// Pauses the session.
    @IBAction private func pauseButtonPressed() {
        guard let session = currentSession else { return }
        healthStore.pause(session)
        timer.stop()
        pauseDate = Date()
    }

    /// Resumes the session.
    @IBAction private func continueButtonPressed() {
        guard let session = currentSession else { return }
        healthStore.resumeWorkoutSession(session)
        pausesIntervals += pauseDate.timeIntervalSinceNow
        let interval = startDate.timeIntervalSinceNow - pausesIntervals
        timer.setDate(Date(timeIntervalSinceNow: interval))
        timer.start()
    }

    /// Pops the interface controller.
    @IBAction private func endButtonPressed() {
        pop()
    }

    // MARK: - HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {

        switch toState {
        case .running:
            pauseButton.setHidden(false)
            continueButton.setHidden(true)
            if fromState == .notStarted {
                startQueries()
            }
        case .paused:
            pauseButton.setHidden(true)
            continueButton.setHidden(false)
        default:
            break
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session fails - \(error)")
    }
}
