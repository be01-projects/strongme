//
//  ContentView.swift
//  StrongMe
//

import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TodayView()
    }
}

#Preview {
    ContentView()
        .environment(HealthKitService())
        .environment(ToastCenter())
        .modelContainer(for: [FoodEntry.self, UsualMeal.self, ReflectionEntry.self, FoodCorrection.self],
                        inMemory: true)
}
