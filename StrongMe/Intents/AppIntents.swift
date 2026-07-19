//
//  AppIntents.swift
//  StrongMe
//
//  "The best logging never opens the app." Siri, Shortcuts, and the
//  Action Button all funnel into the same parser and stores as the talk
//  control. Logging is optimistic — Siri says what was understood, and
//  the app's History/Undo paths are the correction loop. The one
//  exception: distress opens the app for the care response, which should
//  never be compressed into a Siri banner.
//

import AppIntents
import Foundation
import HealthKit
import SwiftData
import SwiftUI

// MARK: - Log anything by saying it

struct LogEntryIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Log a health entry"
    static let description = IntentDescription(
        "Say food, your weight, a reflection, or a target — StrongMe parses and files it.",
        categoryName: "Logging"
    )

    @Parameter(title: "Entry", requestValueDialog: "What would you like to log?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = AppStores.container.mainContext

        // Smart memory first — "log my usual breakfast" costs zero API calls
        if let meal = EntryLogger.usualRequestMeal(in: text) {
            guard let usual = EntryLogger.topUsual(for: meal, context: context) else {
                return .result(
                    dialog: "No usual \(meal) saved yet — log it once in StrongMe and I'll remember it.",
                    view: LogSnippetView(items: [])
                )
            }
            EntryLogger.saveFood(items: usual.items, meal: meal, rawText: text, context: context)
            try? context.save()  // background launches may never autosave
            return .result(
                dialog: "Logged your usual \(meal) — \(Int(usual.proteinGrams.rounded())) grams of protein.",
                view: LogSnippetView(items: usual.items)
            )
        }

        let corrections = EntryLogger.recentCorrections(context: context)
        let (entry, _) = await EntryParser.parse(text, corrections: corrections)

        switch entry.kind {
        case .distress:
            // Never a banner: open the app for the care response. The action
            // is in-memory on purpose — if the user declines Siri's prompt,
            // it must not fire on a later unrelated launch.
            PendingIntentActions.shared.action = .care
            throw needsToContinueInForegroundError("Let's take that into the app.")

        case .food:
            let items = entry.items.map {
                FoodItemRecord(name: $0.name, proteinGrams: $0.proteinG, calories: $0.calories)
            }
            guard !items.isEmpty else {
                return .result(
                    dialog: "I didn't catch any food in that — try naming what you ate.",
                    view: LogSnippetView(items: [])
                )
            }
            EntryLogger.saveFood(items: items, meal: entry.meal, rawText: text, context: context)
            try? context.save()  // background launches may never autosave
            let names = items.map(\.name).joined(separator: ", ")
            let protein = Int(items.reduce(0) { $0 + $1.proteinGrams }.rounded())
            return .result(
                dialog: "Logged: \(names) — about \(protein) grams of protein. Fix anything in StrongMe.",
                view: LogSnippetView(items: items)
            )

        case .weight:
            guard entry.weightValue > 0 else {
                return .result(
                    dialog: "I couldn't find a number in that — try “182 this morning”.",
                    view: LogSnippetView(items: [])
                )
            }
            let health = HealthKitService()
            // Same unit resolution as the in-app path: unspecified → the
            // user's Health preference, not a pounds default
            let usesPounds = entry.weightUnit == "unknown"
                ? await health.prefersPounds()
                : entry.weightUnit != "kg"
            let unit: HKUnit = usesPounds ? .pound() : .gramUnit(with: .kilo)
            do {
                try await health.saveWeight(value: entry.weightValue, unit: unit)
                return .result(
                    dialog: "Weight logged — \(formatted(entry.weightValue)) \(usesPounds ? "pounds" : "kilograms").",
                    view: LogSnippetView(items: [])
                )
            } catch {
                return .result(
                    dialog: "I couldn't save that to Health — check Health permissions in StrongMe.",
                    view: LogSnippetView(items: [])
                )
            }

        case .target:
            guard entry.targetProteinG > 0 else {
                return .result(dialog: "I couldn't find a number in that.", view: LogSnippetView(items: []))
            }
            UserDefaults.standard.set(entry.targetProteinG, forKey: AppSettings.proteinTarget)
            WidgetBridge.publish(context: context)
            return .result(
                dialog: "Protein target set to \(Int(entry.targetProteinG)) grams a day.",
                view: LogSnippetView(items: [])
            )

        case .name:
            let name = entry.userName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return .result(dialog: "I didn't catch the name.", view: LogSnippetView(items: []))
            }
            UserDefaults.standard.set(name, forKey: AppSettings.userName)
            return .result(dialog: "Nice to meet you, \(name).", view: LogSnippetView(items: []))

        case .reflection, .other:
            context.insert(ReflectionEntry(text: text, tags: entry.reflectionTags))
            try? context.save()  // background launches may never autosave
            return .result(
                dialog: "Kept in your words — never scored.",
                view: LogSnippetView(items: [])
            )
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

// MARK: - Log a usual, fully hands-free

enum MealSlot: String, AppEnum {
    case breakfast, lunch, dinner, snack

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal"
    static let caseDisplayRepresentations: [MealSlot: DisplayRepresentation] = [
        .breakfast: "Breakfast",
        .lunch: "Lunch",
        .dinner: "Dinner",
        .snack: "Snack",
    ]
}

struct LogUsualIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a usual meal"
    static let description = IntentDescription(
        "One breath logs the meal you usually have.",
        categoryName: "Logging"
    )

    @Parameter(title: "Meal")
    var meal: MealSlot

    static var parameterSummary: some ParameterSummary {
        Summary("Log my usual \(\.$meal)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = AppStores.container.mainContext
        guard let usual = EntryLogger.topUsual(for: meal.rawValue, context: context) else {
            return .result(
                dialog: "No usual \(meal.rawValue) saved yet — log it once in StrongMe and I'll remember it.",
                view: LogSnippetView(items: [])
            )
        }
        EntryLogger.saveFood(items: usual.items, meal: meal.rawValue, rawText: "usual \(meal.rawValue)", context: context)
        try? context.save()  // background launches may never autosave
        return .result(
            dialog: "Logged your usual \(meal.rawValue) — \(Int(usual.proteinGrams.rounded())) grams of protein.",
            view: LogSnippetView(items: usual.items)
        )
    }
}

// MARK: - Open straight into the talk control (Action Button / widget)

struct TalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to StrongMe"
    static let description = IntentDescription(
        "Opens StrongMe listening — say anything and it's filed.",
        categoryName: "Logging"
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // In-memory and observed by TodayContent — works whether the app was
        // cold, backgrounded, or already frontmost (a UserDefaults flag only
        // consumed on scenePhase changes misses the already-active case)
        PendingIntentActions.shared.action = .openCapture
        return .result()
    }
}

// MARK: - Siri phrases

struct StrongMeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogEntryIntent(),
            phrases: [
                "Log in \(.applicationName)",
                "Log food in \(.applicationName)",
                "Log a meal in \(.applicationName)",
                "Log my weight in \(.applicationName)",
            ],
            shortTitle: "Log",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: LogUsualIntent(),
            phrases: [
                "Log my usual \(\.$meal) in \(.applicationName)",
                "Log my \(\.$meal) in \(.applicationName)",
            ],
            shortTitle: "Log a usual",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: TalkIntent(),
            phrases: [
                "Talk to \(.applicationName)",
            ],
            shortTitle: "Talk",
            systemImageName: "waveform"
        )
    }
}

// MARK: - Snippet (what Siri shows under the dialog)

struct LogSnippetView: View {
    let items: [FoodItemRecord]

    private var protein: Int { Int(items.reduce(0) { $0 + $1.proteinGrams }.rounded()) }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(Palette.indigo).frame(width: 6, height: 6)
                    Text("LOGGED")
                        .font(AppFont.ui(11, .semibold))
                        .kerning(0.6)
                        .foregroundStyle(Palette.indigo)
                    Spacer()
                    Text("+\(protein)g protein")
                        .font(AppFont.ui(12, .bold))
                        .foregroundStyle(Palette.apricot)
                }
                FlowLayout(spacing: 7) {
                    ForEach(items) { item in
                        Text(item.name)
                            .font(AppFont.ui(13, .medium))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
                    }
                }
            }
            .padding(16)
            .background(Palette.app)
        }
    }
}
