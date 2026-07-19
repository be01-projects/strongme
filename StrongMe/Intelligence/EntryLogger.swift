//
//  EntryLogger.swift
//  StrongMe
//
//  The logging core shared by the capture sheet and App Intents — the
//  same save paths whether an entry arrives by tap, talk, or Siri.
//

import Foundation
import SwiftData

@MainActor
enum EntryLogger {

    /// Insert a food entry and teach the usuals in one step.
    @discardableResult
    static func saveFood(
        items: [FoodItemRecord],
        meal: String,
        rawText: String,
        date: Date = .now,
        context: ModelContext
    ) -> FoodEntry {
        let entry = FoodEntry(date: date, mealLabel: meal, items: items, rawText: rawText)
        context.insert(entry)
        UsualLearner.record(items: items, meal: meal, context: context)
        return entry
    }

    /// The last 10 chip corrections, for the parser prompt.
    static func recentCorrections(context: ModelContext) -> [(String, String)] {
        var descriptor = FetchDescriptor<FoodCorrection>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 10
        let fixes = (try? context.fetch(descriptor)) ?? []
        return fixes.map { ($0.original, $0.corrected) }
    }

    /// "Log my usual breakfast" — the whole utterance must be the command,
    /// and it must contain an explicit "log" or "usual". Plain statements
    /// like "I had lunch" describe what happened and belong to the parser —
    /// hijacking them would silently file the stored usual as fact.
    static func usualRequestMeal(in text: String) -> String? {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let pattern = /^(?:log\s+(?:my\s+)?(?:usual\s+)?|(?:my\s+)?usual\s+)(breakfast|lunch|dinner|snack)(?:\s+please)?$/
        guard let match = normalized.firstMatch(of: pattern) else { return nil }
        return String(match.1)
    }

    /// The most-established *learned* usual for a meal. Seeds are excluded:
    /// they exist so the chip row isn't empty, and tapping one is an explicit
    /// choice — but recall ("log my usual lunch") must never file food the
    /// user has never actually logged.
    static func topUsual(for meal: String, context: ModelContext) -> UsualMeal? {
        let all = (try? context.fetch(FetchDescriptor<UsualMeal>())) ?? []
        return all
            .filter { $0.mealLabel == meal && !$0.isSeed }
            .max { ($0.timesLogged, $0.lastUsed) < ($1.timesLogged, $1.lastUsed) }
    }
}
