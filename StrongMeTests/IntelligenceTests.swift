//
//  IntelligenceTests.swift
//  StrongMeTests
//
//  Pins the intelligence layer: the parsing/recall regexes, usual learning
//  rules, the offline parser's routing, the coach cache stamp, and the
//  app↔widget snapshot contract. These are exactly the behaviors past code
//  reviews caught regressions in — keep them locked.
//

import Foundation
import SwiftData
import Testing
@testable import StrongMe

// MARK: - Usual recall ("log my usual breakfast")

@Suite struct UsualRecallTests {

    @Test func explicitFormsMatch() {
        #expect(EntryLogger.usualRequestMeal(in: "log my usual breakfast") == "breakfast")
        #expect(EntryLogger.usualRequestMeal(in: "usual lunch") == "lunch")
        #expect(EntryLogger.usualRequestMeal(in: "Log usual dinner please.") == "dinner")
        #expect(EntryLogger.usualRequestMeal(in: "my usual snack") == "snack")
        #expect(EntryLogger.usualRequestMeal(in: "log breakfast") == "breakfast")
    }

    /// The review bug: "I had lunch" is a statement of fact, and hijacking it
    /// would silently file the stored usual as something the user never said.
    @Test func statementsAreNotRecall() {
        #expect(EntryLogger.usualRequestMeal(in: "I had lunch") == nil)
        #expect(EntryLogger.usualRequestMeal(in: "had my usual breakfast") == nil)
        #expect(EntryLogger.usualRequestMeal(in: "what's a usual breakfast") == nil)
        #expect(EntryLogger.usualRequestMeal(in: "log my usual breakfast and a coffee") == nil)
        #expect(EntryLogger.usualRequestMeal(in: "usual") == nil)
    }
}

// MARK: - In-memory store helper

/// Returns the container, not just a context — a ModelContext does not keep
/// its container alive, and using one after the container deallocates traps
/// inside SwiftData.
@MainActor
private func makeStore() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: FoodEntry.self, UsualMeal.self, ReflectionEntry.self, FoodCorrection.self,
        configurations: config
    )
}

private let eggs = [FoodItemRecord(name: "3 eggs", proteinGrams: 19, calories: 215)]
private let shake = [FoodItemRecord(name: "Protein shake", proteinGrams: 30, calories: 180)]

// MARK: - topUsual (Siri recall source)

@MainActor
@Suite struct TopUsualTests {

    /// The review bug: recall through a seed would file food the user has
    /// never actually logged.
    @Test func seedsAreNeverRecalled() throws {
        let store = try makeStore()
        let context = store.mainContext
        context.insert(UsualMeal(name: "Seeded bowl", items: shake, timesLogged: 9,
                                 isSeed: true, mealLabel: "lunch"))
        #expect(EntryLogger.topUsual(for: "lunch", context: context) == nil)

        context.insert(UsualMeal(name: "3 eggs", items: eggs, timesLogged: 1, mealLabel: "lunch"))
        #expect(EntryLogger.topUsual(for: "lunch", context: context)?.name == "3 eggs")
    }

    @Test func mostEstablishedWinsPerMeal() throws {
        let store = try makeStore()
        let context = store.mainContext
        context.insert(UsualMeal(name: "3 eggs", items: eggs, timesLogged: 2, mealLabel: "breakfast"))
        context.insert(UsualMeal(name: "Protein shake", items: shake, timesLogged: 7, mealLabel: "breakfast"))
        context.insert(UsualMeal(name: "Big dinner", items: shake, timesLogged: 20, mealLabel: "dinner"))
        #expect(EntryLogger.topUsual(for: "breakfast", context: context)?.name == "Protein shake")
    }
}

// MARK: - Usual learning

@MainActor
@Suite struct UsualLearnerTests {

    @Test func confirmedMealBecomesUsual() throws {
        let store = try makeStore()
        let context = store.mainContext
        UsualLearner.record(items: eggs, meal: "breakfast", context: context)
        let all = try context.fetch(FetchDescriptor<UsualMeal>())
        #expect(all.count == 1)
        #expect(all.first?.timesLogged == 1)
        #expect(all.first?.mealLabel == "breakfast")
        #expect(all.first?.isSeed == false)
    }

    /// The review bug: one off-schedule dinner of a 20-time breakfast must
    /// not break "log my usual breakfast".
    @Test func mealLabelSticksOnceSet() throws {
        let store = try makeStore()
        let context = store.mainContext
        UsualLearner.record(items: eggs, meal: "breakfast", context: context)
        UsualLearner.record(items: eggs, meal: "dinner", context: context)
        let usual = try #require(try context.fetch(FetchDescriptor<UsualMeal>()).first)
        #expect(usual.mealLabel == "breakfast")
        #expect(usual.timesLogged == 2)
    }

    @Test func unknownLabelUpgradesWhenLearned() throws {
        let store = try makeStore()
        let context = store.mainContext
        UsualLearner.record(items: eggs, meal: "unknown", context: context)
        UsualLearner.record(items: eggs, meal: "lunch", context: context)
        let usual = try #require(try context.fetch(FetchDescriptor<UsualMeal>()).first)
        #expect(usual.mealLabel == "lunch")
    }

    @Test func loggingASeedGraduatesIt() throws {
        let store = try makeStore()
        let context = store.mainContext
        context.insert(UsualMeal(name: "Protein shake", items: shake, timesLogged: 0,
                                 isSeed: true, mealLabel: "snack"))
        UsualLearner.record(items: shake, meal: "snack", context: context)
        let usual = try #require(try context.fetch(FetchDescriptor<UsualMeal>()).first)
        #expect(usual.isSeed == false)
        #expect(usual.timesLogged == 1)
    }

    @Test func emptyItemsLearnNothing() throws {
        let store = try makeStore()
        let context = store.mainContext
        UsualLearner.record(items: [], meal: "lunch", context: context)
        #expect(try context.fetch(FetchDescriptor<UsualMeal>()).isEmpty)
    }
}

// MARK: - Offline fallback parser routing

@Suite struct LocalFallbackParserTests {

    /// Non-negotiable: distress wins over everything, and the app must never
    /// chirp "logged!" at it.
    @Test func distressOverridesEverything() {
        #expect(LocalFallbackParser.containsDistressSignals("I want to die"))
        #expect(LocalFallbackParser.parse("I can't go on like this").kind == .distress)
        #expect(LocalFallbackParser.parse("ate lunch but honestly I can't go on").kind == .distress)
        #expect(!LocalFallbackParser.containsDistressSignals("great workout today"))
    }

    @Test func explicitNameOnly() {
        #expect(LocalFallbackParser.parse("call me steve").kind == .name)
        #expect(LocalFallbackParser.parse("call me steve").userName == "Steve")
        // "i'm exhausted" must stay a reflection, never a name
        #expect(LocalFallbackParser.parse("i'm exhausted").kind == .reflection)
    }

    @Test func proteinTarget() {
        let entry = LocalFallbackParser.parse("set my protein target to 160")
        #expect(entry.kind == .target)
        #expect(entry.targetProteinG == 160)
    }

    @Test func weightNeedsContext() {
        let morning = LocalFallbackParser.parse("182 this morning")
        #expect(morning.kind == .weight)
        #expect(morning.weightValue == 182)

        let metric = LocalFallbackParser.parse("83.5 kg on the scale")
        #expect(metric.kind == .weight)
        #expect(metric.weightUnit == "kg")

        // A bare count of food must not become a bodyweight
        #expect(LocalFallbackParser.parse("ate 2 eggs and toast").kind == .food)
    }

    @Test func feelingsBecomeReflections() {
        let entry = LocalFallbackParser.parse("feeling pretty flat today")
        #expect(entry.kind == .reflection)
        #expect(entry.reflectionTags.contains("low energy"))
    }

    @Test func nothingIsEverLost() {
        // Unclassifiable input is kept as a reflection, not dropped
        #expect(LocalFallbackParser.parse("zyzzyva quorum").kind == .reflection)
    }
}

// MARK: - Coach review cache stamp

@Suite struct ReviewStampTests {

    private let base = """
    Date: 2026-07-19 08:00
    Weight: 182.0 lb (7-day avg 182.6)
    Steps today: 4,210
    Protein: 110g avg vs 150g target
    """

    /// Steps tick up all day and the timestamp always moves — neither may
    /// force a fresh (paid) review.
    @Test func volatileLinesDoNotInvalidate() {
        let later = base
            .replacingOccurrences(of: "Steps today: 4,210", with: "Steps today: 9,871")
            .replacingOccurrences(of: "Date: 2026-07-19 08:00", with: "Date: 2026-07-19 18:45")
        #expect(CoachSession.reviewStamp(for: base) == CoachSession.reviewStamp(for: later))
    }

    @Test func realDataChangesInvalidate() {
        let changed = base.replacingOccurrences(of: "Protein: 110g", with: "Protein: 140g")
        #expect(CoachSession.reviewStamp(for: base) != CoachSession.reviewStamp(for: changed))
    }
}

// MARK: - App ↔ widget snapshot contract

@Suite struct WidgetSnapshotTests {

    /// The widget target mirrors this struct by hand. Decoding this frozen
    /// JSON is the contract test: rename a field on either side and this
    /// fails before the widget silently renders placeholders.
    @Test func frozenWireFormatDecodes() throws {
        let wire = Data(#"{"proteinGrams":84,"dayStart":806126400,"targetGrams":150,"styleRaw":"card"}"#.utf8)
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: wire)
        #expect(snapshot.proteinGrams == 84)
        #expect(snapshot.targetGrams == 150)
        #expect(snapshot.styleRaw == "card")
    }

    @Test func roundTrip() throws {
        let snapshot = WidgetSnapshot(dayStart: Calendar.current.startOfDay(for: .now),
                                      proteinGrams: 96, targetGrams: 150, styleRaw: "daybook")
        let data = try JSONEncoder().encode(snapshot)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(back.proteinGrams == snapshot.proteinGrams)
        #expect(back.dayStart == snapshot.dayStart)
    }
}
