//
//  AppSettings.swift
//  StrongMe
//
//  One place for every persisted key. The review flagged the scattered
//  raw strings; the widget made key agreement load-bearing across
//  processes, so now they live here.
//

import Foundation

enum AppSettings {
    /// Shared container for everything the widget extension needs to read.
    /// (The SwiftData store stays app-private — the widget reads a small
    /// published snapshot, never the store.)
    static let appGroupID = "group.com.be01.StrongMe"

    static var groupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // App-side keys (standard defaults)
    static let proteinTarget = "proteinTargetGrams"
    static let userName = "userName"
    static let firstLaunchDate = "firstLaunchDate"
    static let dailyInsightText = "dailyInsightText"
    static let dailyInsightStamp = "dailyInsightStamp"
    static let coachReviewText = "coachReviewText"
    static let coachReviewStamp = "coachReviewStamp"
    // UIStyle.storageKey ("uiStyle") lives in Theme.swift with its enum

    // Cross-process keys (group defaults)
    static let widgetSnapshot = "widgetSnapshot"
}
