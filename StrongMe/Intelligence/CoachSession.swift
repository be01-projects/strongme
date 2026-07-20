//
//  CoachSession.swift
//  StrongMe
//
//  The on-demand coach: pull, not push. Grounded in the trend summary,
//  suggestions not prescriptions, defers on anything medical. The summary
//  it sees is exactly what the user can read in the coach sheet.
//

import CryptoKit
import Foundation
import Observation
import SwiftData

@Observable
final class CoachSession {

    struct Bubble: Identifiable, Equatable {
        enum Role { case user, coach }
        let id = UUID()
        let role: Role
        let text: String
    }

    private(set) var review: String?
    private(set) var bubbles: [Bubble] = []
    private(set) var isThinking = false
    private(set) var dataSummary = ""
    private(set) var isLive = false  // false → key missing, coach is read-only

    /// Wire history for the API: first user turn carries the data snapshot.
    private var apiMessages: [[String: Any]] = []

    static let systemPrompt = """
    You are the coach inside a private, single-user health app. The user's \
    goal is to get healthier and stronger — lose fat, gain muscle. You will \
    be given a DATA snapshot of their real recent numbers and reflections.

    Rules, in priority order:
    1. You are a coach, not a clinician. You are not a doctor or dietitian; \
    defer explicitly on anything medical rather than interpreting it.
    2. Ground everything in their actual figures — cite real numbers from \
    the data ("you've averaged 110g against your 150 target"). Never invent \
    numbers. If the data is missing, say so plainly.
    3. Suggestions, not prescriptions. Offer one or two concrete options in \
    a forgiving tone. Never guilt, never shame, never "you should have".
    4. No calorie obsession — frame around protein, trends, consistency and \
    recovery. Direction over decimal points.
    5. Reflections are the user's own words. You may notice patterns \
    ("you've mentioned feeling flat twice this week") but never interpret \
    or diagnose mood. If a message signals real distress, respond with \
    warmth, don't coach through it, and gently point to real support \
    (in the U.S., call or text 988; findahelpline.com elsewhere).
    6. Stay in scope: analysis and next-step suggestions only. No multi-week \
    workout programming, no full meal plans — if asked, give tonight's/\
    tomorrow's step and suggest a dedicated app for full programming.

    Style: plain language, warm and specific, 2-5 short sentences unless \
    more is genuinely needed. Mark the one or two key numbers or phrases \
    with **bold**. No headings, no bullet lists unless listing food options.
    """

    // MARK: - Lifecycle

    func start(context: ModelContext, health: HealthKitService, proteinTarget: Double) async {
        dataSummary = await TrendSummary.build(context: context, health: health, proteinTarget: proteinTarget)
        isLive = ClaudeClient.isConfigured

        guard isLive else {
            review = "The coach needs an API key (see BUILD_NOTES.md). Once it's set, one tap gets you a plain-language read of your week — grounded in the numbers below, which is all it will ever see."
            return
        }

        let opening = """
        DATA
        \(dataSummary)

        Give me the read: how am I doing? What's working, what's slipping, \
        and one or two concrete suggestions.
        """
        apiMessages = [["role": "user", "content": opening]]

        // Reopening the coach minutes later shouldn't re-run the review —
        // reuse it while the underlying data hasn't changed.
        let stamp = Self.reviewStamp(for: dataSummary)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: AppSettings.coachReviewStamp) == stamp,
           let cached = defaults.string(forKey: AppSettings.coachReviewText), !cached.isEmpty {
            review = cached
            apiMessages.append(["role": "assistant", "content": cached])
            return
        }

        isThinking = true
        defer { isThinking = false }

        do {
            let reply = try await ClaudeClient.completeText(
                system: Self.systemPrompt,
                messages: apiMessages
            )
            apiMessages.append(["role": "assistant", "content": reply])
            review = reply
            defaults.set(reply, forKey: AppSettings.coachReviewText)
            defaults.set(stamp, forKey: AppSettings.coachReviewStamp)
        } catch {
            review = fallbackText(for: error)
        }
    }

    /// Day + the non-volatile summary lines. Steps tick up all day and the
    /// timestamp always moves — neither should force a fresh review.
    /// Internal (not private) so the cache-invalidation rules stay pinned by tests.
    static func reviewStamp(for summary: String) -> String {
        let dayKey = Date.now.formatted(.iso8601.year().month().day())
        let stable = summary
            .split(separator: "\n")
            .filter { !$0.hasPrefix("Date:") && !$0.hasPrefix("Steps today:") }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data((dayKey + stable).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func ask(_ question: String) async {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, isLive, !isThinking else { return }

        bubbles.append(Bubble(role: .user, text: question))
        isThinking = true
        defer { isThinking = false }

        apiMessages.append(["role": "user", "content": question])
        do {
            let reply = try await ClaudeClient.completeText(
                system: Self.systemPrompt,
                messages: apiMessages
            )
            apiMessages.append(["role": "assistant", "content": reply])
            bubbles.append(Bubble(role: .coach, text: reply))
        } catch {
            apiMessages.removeLast()  // keep the wire history consistent
            bubbles.append(Bubble(role: .coach, text: fallbackText(for: error)))
        }
    }

    private func fallbackText(for error: Error) -> String {
        if case ClaudeError.refusal = error {
            return "I'd rather not answer that one — but I'm here for anything about your training, food, sleep or trends."
        }
        return "I couldn't reach the coach just now — the numbers are all still here, so try again in a moment."
    }
}

// MARK: - Daily insight (the passive read at the top of Today)

enum DailyInsight {

    /// One Claude-written sentence or two from the same trend summary.
    /// Falls back to the rule-based InsightEngine when offline/keyless.
    static func generate(summary: String) async -> String? {
        guard ClaudeClient.isConfigured else { return nil }
        let prompt = """
        DATA
        \(summary)

        Write today's single passive insight for the top of the home screen: \
        1-2 sentences, at most ~35 words, calm and forgiving, citing at \
        least one real number or concrete fact from the data. At most one \
        gentle nudge — and none if nothing needs nudging. Mark 1-2 key \
        phrases with **bold**. No greeting, no preamble, plain text only.
        """
        do {
            return try await ClaudeClient.completeText(
                system: CoachSession.systemPrompt,
                messages: [["role": "user", "content": prompt]],
                effort: "low",
                maxTokens: 300
            )
        } catch {
            return nil
        }
    }
}
