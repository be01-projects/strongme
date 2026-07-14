//
//  StrongMeApp.swift
//  StrongMe
//
//  Private, single-user, local-first. No account, no cloud — only the
//  parser/coach calls leave the device, and only with the minimum needed.
//

import SwiftData
import SwiftUI

@main
struct StrongMeApp: App {
    @State private var health = HealthKitService()
    @State private var toast = ToastCenter()

    private let container: ModelContainer = {
        let container = try! ModelContainer(
            for: FoodEntry.self, UsualMeal.self, ReflectionEntry.self, FoodCorrection.self
        )
        SeedData.seedUsualsIfNeeded(context: container.mainContext)
        return container
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
                .environment(toast)
                .preferredColorScheme(.light)  // dark palette is a later pass
        }
        .modelContainer(container)
    }
}
