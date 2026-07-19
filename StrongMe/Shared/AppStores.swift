//
//  AppStores.swift
//  StrongMe
//
//  One SwiftData container shared by the app UI and App Intents — Siri
//  logging writes to the same store the Today screen reads.
//

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
