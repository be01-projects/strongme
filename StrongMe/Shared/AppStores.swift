//
//  AppStores.swift
//  StrongMe
//
//  One SwiftData container shared by the app UI and App Intents — Siri
//  logging writes to the same store the Today screen reads.
//

import Observation
import SwiftData

@MainActor
enum AppStores {
    static let container: ModelContainer = {
        let container = try! ModelContainer(
            for: FoodEntry.self, UsualMeal.self, ReflectionEntry.self, FoodCorrection.self
        )
        SeedData.seedUsualsIfNeeded(context: container.mainContext)
        return container
    }()
}

/// Typed, in-memory bridge from App Intents to the UI. Intents run in the
/// app's process, so no persistence is needed — and none is wanted: a flag
/// that outlived its moment (user declined Siri's open-app prompt, process
/// died) must NOT fire on a later unrelated launch. One optional action
/// also guarantees at most one pending presentation.
@MainActor
@Observable
final class PendingIntentActions {
    static let shared = PendingIntentActions()

    enum Action {
        case openCapture
        case care
    }

    var action: Action?
}
