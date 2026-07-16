//
//  Models.swift
//  StrongMe
//
//  Local-first storage. Everything stays on device; only the coach's
//  trend summary ever leaves it (and the coach isn't in this milestone).
//

import Foundation
import SwiftData

// MARK: - Food

struct FoodItemRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var proteinGrams: Double
    var calories: Double
}

@Model
final class FoodEntry {
    var date: Date
    /// breakfast / lunch / dinner / snack / unknown
    var mealLabel: String
    var items: [FoodItemRecord]
    /// What the user actually said — kept for correction/review later
    var rawText: String

    var proteinGrams: Double { items.reduce(0) { $0 + $1.proteinGrams } }
    var calories: Double { items.reduce(0) { $0 + $1.calories } }

    init(date: Date = .now, mealLabel: String, items: [FoodItemRecord], rawText: String) {
        self.date = date
        self.mealLabel = mealLabel
        self.items = items
        self.rawText = rawText
    }
}

// MARK: - "The usual" — learned one-tap re-logs

@Model
final class UsualMeal {
    var name: String
    var items: [FoodItemRecord]
    var timesLogged: Int
    var lastUsed: Date
    /// Seeded starters get replaced as real habits accumulate
    var isSeed: Bool
    /// Which meal this usually is — powers time-aware chips and
    /// "log my usual breakfast" (default for pre-existing rows)
    var mealLabel: String = "unknown"

    var proteinGrams: Double { items.reduce(0) { $0 + $1.proteinGrams } }
    var calories: Double { items.reduce(0) { $0 + $1.calories } }

    init(name: String, items: [FoodItemRecord], timesLogged: Int = 0, lastUsed: Date = .now,
         isSeed: Bool = false, mealLabel: String = "unknown") {
        self.name = name
        self.items = items
        self.timesLogged = timesLogged
        self.lastUsed = lastUsed
        self.isSeed = isSeed
        self.mealLabel = mealLabel
    }
}

// MARK: - Corrections — how the parser learns

/// When the user fixes a chip ("coffee" → "large oat-milk latte") we remember
/// it and feed recent corrections back into the parser prompt.
@Model
final class FoodCorrection {
    var original: String
    var corrected: String
    var date: Date

    init(original: String, corrected: String, date: Date = .now) {
        self.original = original
        self.corrected = corrected
        self.date = date
    }
}

// MARK: - Reflection

/// Kept in the user's own words. Never scored, never a metric.
@Model
final class ReflectionEntry {
    var date: Date
    var text: String
    /// Light signal tags ("low energy", "work stress") — context, not scores
    var tags: [String]

    init(date: Date = .now, text: String, tags: [String] = []) {
        self.date = date
        self.text = text
        self.tags = tags
    }
}

// MARK: - Seeding

enum SeedData {
    /// Starter "usuals" so the row isn't empty on day one. Real confirmed
    /// meals overtake these by frequency.
    static func seedUsualsIfNeeded(context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<UsualMeal>())) ?? 0
        guard existing == 0 else {
            backfillSeedMealLabels(context: context)
            return
        }

        let seeds: [(String, String, [FoodItemRecord])] = [
            ("Yogurt + berries", "breakfast", [FoodItemRecord(name: "Greek yogurt + berries", proteinGrams: 24, calories: 180)]),
            ("Eggs + toast", "breakfast", [FoodItemRecord(name: "3 eggs", proteinGrams: 19, calories: 215),
                                           FoodItemRecord(name: "toast", proteinGrams: 3, calories: 95)]),
            ("Protein shake", "snack", [FoodItemRecord(name: "Protein shake", proteinGrams: 30, calories: 180)]),
            ("Chicken bowl", "lunch", [FoodItemRecord(name: "Chicken bowl", proteinGrams: 40, calories: 620)]),
        ]
        for (name, meal, items) in seeds {
            context.insert(UsualMeal(name: name, items: items, isSeed: true, mealLabel: meal))
        }
    }

    /// Installs from before usuals learned meal labels have rows stuck on
    /// "unknown" — give the known seeds their labels once.
    private static func backfillSeedMealLabels(context: ModelContext) {
        let labels: [String: String] = [
            "Yogurt + berries": "breakfast",
            "Eggs + toast": "breakfast",
            "Protein shake": "snack",
            "Chicken bowl": "lunch",
        ]
        let descriptor = FetchDescriptor<UsualMeal>(
            predicate: #Predicate { $0.mealLabel == "unknown" && $0.isSeed }
        )
        for usual in (try? context.fetch(descriptor)) ?? [] {
            if let meal = labels[usual.name] { usual.mealLabel = meal }
        }
    }
}
