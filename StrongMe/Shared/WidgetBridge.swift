//
//  WidgetBridge.swift
//  StrongMe
//
//  The widgets never open the SwiftData store — the app publishes a small
//  JSON snapshot to the App Group whenever the day's numbers change, and
//  the widget renders only that. (WidgetSnapshot is mirrored by hand in
//  StrongMeWidgets; the two structs must stay field-compatible.)
//

import Foundation
import SwiftData
import WidgetKit

struct WidgetSnapshot: Codable {
    var dayStart: Date
    var proteinGrams: Int
    var targetGrams: Int
    var styleRaw: String
}

@MainActor
enum WidgetBridge {

    /// Recompute today's protein and hand the widgets a fresh snapshot.
    /// Cheap enough to call after every mutation and on backgrounding.
    static func publish(context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: .now)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        let todaysFood = (try? context.fetch(descriptor)) ?? []
        let protein = todaysFood.reduce(0) { $0 + $1.proteinGrams }

        let storedTarget = UserDefaults.standard.double(forKey: AppSettings.proteinTarget)
        let snapshot = WidgetSnapshot(
            dayStart: dayStart,
            proteinGrams: Int(protein.rounded()),
            targetGrams: Int((storedTarget > 0 ? storedTarget : 150).rounded()),
            styleRaw: UIStyle.current.rawValue
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            AppSettings.groupDefaults.set(data, forKey: AppSettings.widgetSnapshot)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
