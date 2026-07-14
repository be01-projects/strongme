//
//  InsightEngine.swift
//  StrongMe
//
//  The daily read at the top of Today. Rule-based for this milestone —
//  documented stub for the Claude-generated insight that arrives with the
//  coach. One plain-language sentence or two, calm and forgiving, never
//  a guilt trip. Markdown ** ** marks the emphasis spans.
//

import Foundation

enum InsightEngine {

    static func dailyRead(
        snapshot: HealthSnapshot,
        proteinToday: Double,
        proteinTarget: Double,
        hasLoggedFoodToday: Bool
    ) -> String {
        var observations: [String] = []
        var nudge: String?

        // ---- observations (what's working) ----
        if snapshot.trainedToday {
            observations.append("You've **already trained today** — that's the hard part done.")
        } else if snapshot.workoutsThisWeek >= 3 {
            observations.append("You've trained **\(snapshot.workoutsThisWeek) times this week** and the rhythm is holding.")
        } else if snapshot.workoutsThisWeek > 0 {
            observations.append("**\(snapshot.workoutsThisWeek) session\(snapshot.workoutsThisWeek == 1 ? "" : "s")** in this week so far.")
        }

        if let change = snapshot.weightChangeTwoWeeks, change <= -0.5 {
            let formatted = String(format: "%.1f", abs(change))
            observations.append("Weight is **down \(formatted) \(snapshot.weightUnitLabel) over two weeks** — a healthy pace.")
        }

        if let steps = snapshot.stepsToday, let avg = snapshot.stepsDailyAverage, avg > 0,
           Double(steps) > Double(avg) * 0.9 {
            observations.append("Steps are **right on your usual day**.")
        }

        if let sleep = snapshot.sleepLastNight, sleep >= 7 * 3600 {
            observations.append("Sleep came in **solid** last night.")
        }

        // ---- one gentle nudge, max ----
        let hour = Calendar.current.component(.hour, from: .now)
        let proteinRatio = proteinTarget > 0 ? proteinToday / proteinTarget : 0
        if hasLoggedFoodToday || hour >= 12 {
            if proteinRatio < 0.4 && hour >= 12 {
                nudge = "Protein's the one soft spot so far — **an easy win is a bigger next meal.**"
            } else if proteinRatio >= 1 {
                nudge = "Protein target **already hit** — nothing left to chase today."
            }
        }
        if nudge == nil, let sleep = snapshot.sleepLastNight, sleep < 6 * 3600 {
            nudge = "Last night ran short — **an easier day is a fine choice.**"
        }

        // ---- compose ----
        if observations.isEmpty && nudge == nil {
            if !snapshot.trainedToday && snapshot.stepsToday == nil {
                return "Once Health access is set up, steps, sleep and training fill in **on their own**. Anything you eat — just say it in one sentence."
            }
            return "A quiet start. Nothing to fix, nothing to chase — **log a meal whenever you're ready.**"
        }

        var parts = Array(observations.prefix(2))
        if let nudge { parts.append(nudge) }
        return parts.joined(separator: " ")
    }
}
