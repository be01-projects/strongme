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
    @Environment(\.scenePhase) private var scenePhase
    @State private var health = HealthKitService()
    @State private var toast = ToastCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
                .environment(toast)
                .preferredColorScheme(.light)  // dark palette is a later pass
                .onOpenURL { url in
                    // Widget deep links, routed through the same in-process
                    // channel the intents use.
                    switch url.host() {
                    case "talk", "capture": PendingIntentActions.shared.action = .openCapture
                    case "protein": PendingIntentActions.shared.action = .protein
                    default: break
                    }
                }
        }
        .modelContainer(AppStores.container)  // shared with App Intents
        .onChange(of: scenePhase) { _, phase in
            // One publish on the way out covers every in-app mutation —
            // deletes, edits, undo, target changes — without instrumenting
            // each closure. Saves also publish directly (Siri never
            // backgrounds us through here).
            if phase == .background || phase == .inactive {
                WidgetBridge.publish(context: AppStores.container.mainContext)
            }
        }
    }
}
