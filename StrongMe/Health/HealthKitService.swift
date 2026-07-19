//
//  HealthKitService.swift
//  StrongMe
//
//  Tier 0 — automatic. If Apple Health already knows it, never ask.
//  Reads steps, sleep, workouts, bodyweight, resting HR; writes bodyweight
//  (the one Tier-1 value we file back so Health stays the source of truth).
//

import Foundation
import HealthKit
import Observation

struct HealthSnapshot {
    var stepsToday: Int?
    /// 30-day average of daily step totals
    var stepsDailyAverage: Int?
    var sleepLastNight: TimeInterval?
    var workoutsThisWeek: Int = 0
    var trainedToday: Bool = false
    var latestWeight: Double?          // in display unit
    var weightChangeTwoWeeks: Double?  // in display unit; negative = down
    var usesPounds: Bool = true
    var restingHeartRate: Double?

    var weightUnitLabel: String { usesPounds ? "lb" : "kg" }
}

@Observable
final class HealthKitService {
    private let store = HKHealthStore()
    private(set) var snapshot = HealthSnapshot()
    private(set) var isAvailable = HKHealthStore.isHealthDataAvailable()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.bodyMass),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        // UI tests / scripted screenshots: launch with -skip-health-auth
        guard !ProcessInfo.processInfo.arguments.contains("-skip-health-auth") else { return }
        do {
            try await store.requestAuthorization(
                toShare: [HKQuantityType(.bodyMass)],
                read: readTypes
            )
        } catch {
            // Denied or restricted: the Today screen degrades to "no data yet"
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard isAvailable else { return }
        var snap = HealthSnapshot()

        // Preferred mass unit (assume a US-style lb display if lookup fails)
        if let units = try? await store.preferredUnits(for: [HKQuantityType(.bodyMass)]),
           let unit = units[HKQuantityType(.bodyMass)] {
            snap.usesPounds = unit == .pound()
        }

        async let steps = stepsToday()
        async let avg = stepsDailyAverage()
        async let sleep = sleepLastNight()
        async let workouts = workoutsThisWeek()
        async let weight = weightTrend(usesPounds: snap.usesPounds)
        async let rhr = latestRestingHeartRate()

        snap.stepsToday = await steps
        snap.stepsDailyAverage = await avg
        snap.sleepLastNight = await sleep
        (snap.workoutsThisWeek, snap.trainedToday) = await workouts
        (snap.latestWeight, snap.weightChangeTwoWeeks) = await weight
        snap.restingHeartRate = await rhr

        snapshot = snap
    }

    /// The user's preferred bodyweight unit, without needing a full refresh —
    /// used by the Siri path where no snapshot has been loaded.
    func prefersPounds() async -> Bool {
        guard isAvailable else { return true }
        if let units = try? await store.preferredUnits(for: [HKQuantityType(.bodyMass)]),
           let unit = units[HKQuantityType(.bodyMass)] {
            return unit == .pound()
        }
        return true
    }

    // MARK: - Writes

    @discardableResult
    func saveWeight(value: Double, unit: HKUnit, date: Date = .now) async throws -> HKQuantitySample {
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: quantity,
            start: date, end: date
        )
        try await store.save(sample)
        await refresh()
        return sample
    }

    /// Delete a sample this app wrote (undo, or clearing a misheard weight).
    func deleteSample(_ sample: HKObject) async {
        try? await store.delete(sample)
        await refresh()
    }

    // MARK: - Queries

    private func stepsToday() async -> Int? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum
        )
        guard let result = try? await descriptor.result(for: store),
              let sum = result.sumQuantity() else { return nil }
        return Int(sum.doubleValue(for: HKUnit.count()))
    }

    private func stepsDailyAverage() async -> Int? {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -30, to: anchor) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: anchor)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }
        var totals: [Double] = []
        collection.enumerateStatistics(from: start, to: anchor) { stats, _ in
            if let sum = stats.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                totals.append(sum)
            }
        }
        guard !totals.isEmpty else { return nil }
        return Int(totals.reduce(0, +) / Double(totals.count))
    }

    /// Sums asleep-stage samples from yesterday 6pm through today noon.
    /// (Overlapping multi-source samples can double-count; fine for trends.)
    private func sleepLastNight() async -> TimeInterval? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        guard let windowStart = calendar.date(byAdding: .hour, value: -6, to: todayStart),
              let windowEnd = calendar.date(byAdding: .hour, value: 12, to: todayStart) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let total = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return total > 0 ? total : nil
    }

    private func workoutsThisWeek() async -> (count: Int, trainedToday: Bool) {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return (0, false) }
        let predicate = HKQuery.predicateForSamples(withStart: weekStart, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return (0, false) }
        let todayStart = calendar.startOfDay(for: .now)
        let trainedToday = workouts.contains { $0.startDate >= todayStart }
        return (workouts.count, trainedToday)
    }

    private func weightTrend(usesPounds: Bool) async -> (latest: Double?, changeTwoWeeks: Double?) {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -60, to: .now) else { return (nil, nil) }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store), let latest = samples.first else {
            return (nil, nil)
        }
        let unit: HKUnit = usesPounds ? .pound() : .gramUnit(with: .kilo)
        let latestValue = latest.quantity.doubleValue(for: unit)

        // Nearest sample to 14 days before the latest reading
        let target = latest.startDate.addingTimeInterval(-14 * 86_400)
        let past = samples.min {
            abs($0.startDate.timeIntervalSince(target)) < abs($1.startDate.timeIntervalSince(target))
        }
        var change: Double?
        if let past, past !== latest,
           abs(past.startDate.timeIntervalSince(target)) < 7 * 86_400 {
            change = latestValue - past.quantity.doubleValue(for: unit)
        }
        return (latestValue, change)
    }

    // MARK: - Coach & history queries

    /// Distinct days with a workout in the last `lastDays` days, oldest first.
    func workoutDates(lastDays: Int) async -> [Date] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -lastDays, to: calendar.startOfDay(for: .now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        var days: [Date] = []
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            if days.last != day { days.append(day) }
        }
        return days
    }

    /// Nightly sleep totals for the last `lastNights` nights, oldest first.
    func nightlySleep(lastNights: Int) async -> [(night: Date, duration: TimeInterval)] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -lastNights, to: todayStart),
              let windowStart = calendar.date(byAdding: .hour, value: -6, to: start) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return [] }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        // Attribute each asleep sample to the night it belongs to (6pm cutoff)
        var byNight: [Date: TimeInterval] = [:]
        for sample in samples where asleepValues.contains(sample.value) {
            let anchor = calendar.startOfDay(for: sample.startDate.addingTimeInterval(6 * 3600))
            byNight[anchor, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }
        return byNight.keys.sorted().map { ($0, byNight[$0]!) }
    }

    /// Average nightly sleep across the last `lastDays` nights (nights with data only).
    func sleepAverage(lastDays: Int) async -> TimeInterval? {
        let nights = await nightlySleep(lastNights: lastDays)
        guard !nights.isEmpty else { return nil }
        return nights.map(\.duration).reduce(0, +) / Double(nights.count)
    }

    /// Daily step totals for the last `lastDays` days (days with data only), oldest first.
    func dailySteps(lastDays: Int) async -> [(day: Date, steps: Int)] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -lastDays, to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        var days: [(Date, Int)] = []
        collection.enumerateStatistics(from: start, to: .now) { stats, _ in
            if let sum = stats.sumQuantity()?.doubleValue(for: HKUnit.count()), sum > 0 {
                days.append((stats.startDate, Int(sum)))
            }
        }
        return days
    }

    /// All workouts in the last `lastDays` days, newest first.
    func workoutHistory(lastDays: Int) async -> [WorkoutInfo] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -lastDays, to: calendar.startOfDay(for: .now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        return workouts.map {
            WorkoutInfo(
                name: Self.workoutName($0.workoutActivityType),
                minutes: Int($0.duration / 60),
                start: $0.startDate
            )
        }
    }

    /// All weight readings in the last `lastDays` days, newest first.
    func weightHistory(lastDays: Int) async -> [WeightReading] {
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -lastDays, to: calendar.startOfDay(for: .now)) else { return [] }
        let usesPounds = snapshot.usesPounds
        let unit: HKUnit = usesPounds ? .pound() : .gramUnit(with: .kilo)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { Self.reading($0, unit: unit, usesPounds: usesPounds) }
    }

    struct WorkoutInfo: Identifiable {
        let id = UUID()
        let name: String
        let minutes: Int
        let start: Date
    }

    struct WeightReading: Identifiable {
        let id = UUID()
        let value: Double
        let unitLabel: String
        let date: Date
        /// Only readings this app wrote can be deleted; a watch or smart
        /// scale's samples belong to Health.
        let isFromThisApp: Bool
        let sample: HKQuantitySample?
    }

    func workouts(on day: Date) async -> [WorkoutInfo] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let workouts = try? await descriptor.result(for: store) else { return [] }
        return workouts.map {
            WorkoutInfo(
                name: Self.workoutName($0.workoutActivityType),
                minutes: Int($0.duration / 60),
                start: $0.startDate
            )
        }
    }

    func weightReadings(on day: Date) async -> [WeightReading] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        let usesPounds = snapshot.usesPounds
        let unit: HKUnit = usesPounds ? .pound() : .gramUnit(with: .kilo)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { Self.reading($0, unit: unit, usesPounds: usesPounds) }
    }

    private static func reading(_ sample: HKQuantitySample, unit: HKUnit, usesPounds: Bool) -> WeightReading {
        let ownBundle = sample.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier
        return WeightReading(
            value: sample.quantity.doubleValue(for: unit),
            unitLabel: usesPounds ? "lb" : "kg",
            date: sample.startDate,
            isFromThisApp: ownBundle,
            sample: ownBundle ? sample : nil
        )
    }

    /// Day numbers within `month` that have a workout or weight reading —
    /// used for the calm calendar markers.
    func healthActivityDays(in month: DateInterval) async -> Set<Int> {
        let calendar = Calendar.current
        var days = Set<Int>()

        let predicate = HKQuery.predicateForSamples(withStart: month.start, end: month.end)
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: []
        )
        if let workouts = try? await workoutDescriptor.result(for: store) {
            for workout in workouts { days.insert(calendar.component(.day, from: workout.startDate)) }
        }

        let weightDescriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: []
        )
        if let samples = try? await weightDescriptor.result(for: store) {
            for sample in samples { days.insert(calendar.component(.day, from: sample.startDate)) }
        }
        return days
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Ride"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .swimming: "Swim"
        case .rowing: "Row"
        case .hiking: "Hike"
        case .coreTraining: "Core"
        case .pilates: "Pilates"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stairs"
        default: "Workout"
        }
    }

    private func latestRestingHeartRate() async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        guard let samples = try? await descriptor.result(for: store),
              let latest = samples.first else { return nil }
        return latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }
}
