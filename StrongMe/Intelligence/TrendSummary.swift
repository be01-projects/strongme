//
//  TrendSummary.swift
//  StrongMe
//
//  The compact trend summary that grounds the coach. This is the ONE place
//  data leaves the device, so it's built as plain text the user can read
//  verbatim in the coach sheet ("What your coach can see"). Send the
//  minimum: aggregates and short reflection excerpts, never raw history.
//

import Foundation
import SwiftData

enum TrendSummary {

    static func build(
        context: ModelContext,
        health: HealthKitService,
        proteinTarget: Double
    ) async -> String {
        let calendar = Calendar.current
        let now = Date.now
        let todayStart = calendar.startOfDay(for: now)
        var lines: [String] = []

        lines.append("Date: \(now.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))")
        lines.append("Protein target: \(Int(proteinTarget))g/day")

        // ---- Protein by day, last 7 days (SwiftData) ----
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: todayStart) {
            let descriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate { $0.date >= weekAgo },
                sortBy: [SortDescriptor(\.date)]
            )
            let entries = (try? context.fetch(descriptor)) ?? []
            var byDay: [Date: Double] = [:]
            for entry in entries {
                byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.proteinGrams
            }
            if byDay.isEmpty {
                lines.append("Protein, last 7 days: no meals logged")
            } else {
                let days = byDay.keys.sorted().map { day in
                    "\(day.formatted(.dateTime.weekday(.abbreviated))) \(Int(byDay[day]!.rounded()))g"
                }
                lines.append("Protein by day, last 7 days: " + days.joined(separator: ", "))
            }

            // Today's meals (helps "what should I eat tonight")
            let todaysMeals = entries.filter { $0.date >= todayStart }
            if !todaysMeals.isEmpty {
                let meals = todaysMeals.map { entry in
                    let items = entry.items.map(\.name).joined(separator: ", ")
                    return "\(entry.mealLabel): \(items) (\(Int(entry.proteinGrams.rounded()))g)"
                }
                lines.append("Today's meals: " + meals.joined(separator: " · "))
            } else {
                lines.append("Today's meals: none logged yet")
            }
        }

        // ---- Health (Tier 0) ----
        let snap = health.snapshot
        let workoutDates = await health.workoutDates(lastDays: 14)
        let trainingDays = workoutDates.map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        lines.append("Training sessions, last 14 days: \(workoutDates.count)"
                     + (trainingDays.isEmpty ? "" : " (\(trainingDays.joined(separator: ", ")))"))
        lines.append("Trained today: \(snap.trainedToday ? "yes" : "no")")

        if let weight = snap.latestWeight {
            var line = "Weight: \(String(format: "%.1f", weight)) \(snap.weightUnitLabel)"
            if let change = snap.weightChangeTwoWeeks {
                line += String(format: " (%+.1f over 2 weeks)", change)
            }
            lines.append(line)
        } else {
            lines.append("Weight: no readings")
        }

        if let sleep = snap.sleepLastNight {
            lines.append("Sleep last night: \(hoursMinutes(sleep))")
        }
        if let avg = await health.sleepAverage(lastDays: 7) {
            lines.append("Sleep 7-day average: \(hoursMinutes(avg))")
        }
        if let steps = snap.stepsToday {
            var line = "Steps today: \(steps)"
            if let avg = snap.stepsDailyAverage { line += " (30-day daily average \(avg))" }
            lines.append(line)
        }
        if let rhr = snap.restingHeartRate {
            lines.append("Resting heart rate: \(Int(rhr)) bpm")
        }

        // ---- Reflections, last 7 days (short excerpts + tags) ----
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) {
            var descriptor = FetchDescriptor<ReflectionEntry>(
                predicate: #Predicate { $0.date >= weekAgo },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = 5
            let reflections = (try? context.fetch(descriptor)) ?? []
            if reflections.isEmpty {
                lines.append("Reflections, last 7 days: none")
            } else {
                lines.append("Reflections, last 7 days (user's own words):")
                for reflection in reflections.reversed() {
                    let day = reflection.date.formatted(.dateTime.weekday(.abbreviated))
                    let text = String(reflection.text.prefix(140))
                    let tags = reflection.tags.isEmpty ? "" : " [\(reflection.tags.joined(separator: ", "))]"
                    lines.append("- \(day): \"\(text)\"\(tags)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func hoursMinutes(_ interval: TimeInterval) -> String {
        "\(Int(interval) / 3600)h \((Int(interval) % 3600) / 60)m"
    }
}
