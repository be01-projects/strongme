//
//  EntryParser.swift
//  StrongMe
//
//  The routing layer: one sentence in → a classified, structured entry out.
//  Claude does the real parsing; a small on-device fallback keeps the app
//  usable with no API key or no network (clearly labeled as a rough guess).
//

import Foundation

// MARK: - Result types

struct ParsedEntry: Codable {
    enum Kind: String, Codable {
        case food, weight, reflection, distress, target, other
    }

    var kind: Kind
    var meal: String                // breakfast | lunch | dinner | snack | unknown
    var items: [ParsedFoodItem]
    var weightValue: Double
    var weightUnit: String          // lb | kg | unknown
    var reflectionTags: [String]
    var targetProteinG: Double      // for kind == .target
    var summary: String

    enum CodingKeys: String, CodingKey {
        case kind, meal, items
        case weightValue = "weight_value"
        case weightUnit = "weight_unit"
        case reflectionTags = "reflection_tags"
        case targetProteinG = "target_protein_g"
        case summary
    }
}

struct ParsedFoodItem: Codable {
    var name: String
    var proteinG: Double
    var calories: Double

    enum CodingKeys: String, CodingKey {
        case name
        case proteinG = "protein_g"
        case calories
    }
}

enum ParseSource {
    case claude
    case onDeviceFallback
}

// MARK: - Parser

enum EntryParser {

    /// Parse a spoken/typed sentence. `corrections` are past chip fixes the
    /// model should learn from ("coffee" usually means "large oat-milk latte").
    static func parse(_ text: String, corrections: [(String, String)]) async -> (ParsedEntry, ParseSource) {
        if ClaudeClient.isConfigured {
            do {
                let data = try await ClaudeClient.completeJSON(
                    system: systemPrompt(corrections: corrections),
                    user: text,
                    schema: schema
                )
                var entry = try JSONDecoder().decode(ParsedEntry.self, from: data)
                // Belt and suspenders on the one guardrail that can't miss:
                // if the on-device screen sees clear distress signals, the
                // care response wins regardless of the model's routing.
                if entry.kind != .distress, LocalFallbackParser.containsDistressSignals(text) {
                    entry.kind = .distress
                }
                return (entry, .claude)
            } catch {
                // Network/API trouble: degrade to the local guess rather than
                // making the user retype.
            }
        }
        return (LocalFallbackParser.parse(text), .onDeviceFallback)
    }

    // MARK: Prompt

    private static func systemPrompt(corrections: [(String, String)]) -> String {
        var prompt = """
        You are the parsing layer inside a private, single-user iOS health app. \
        The user narrates one short entry (spoken or typed). Classify it and \
        extract structured data. Never ask questions; make your best estimate.

        Classification:
        - "food": the entry describes something eaten or drunk.
        - "weight": the entry reports bodyweight (e.g. "182 this morning").
        - "reflection": free-form journaling about their day, mood, energy, \
        stress, sleep quality, or training feelings — anything that isn't \
        structured data. Keep it in their words; extract 1-3 short lowercase \
        signal tags (e.g. "low energy", "work stress", "skipped training", \
        "slept well").
        - "distress": the entry signals serious emotional distress, hopelessness, \
        or thoughts of self-harm. When uncertain between reflection and distress \
        and the content is concerning, choose distress — err on the side of care.
        - "target": the user is setting their daily protein target (e.g. "set \
        my protein target to 160"). Put the grams in target_protein_g.
        - "other": none of the above (questions, commands, noise).

        Food rules:
        - Split into individual items. Estimate rough calories and protein for \
        typical portions — trends over precision, protein matters most.
        - Round protein to whole grams, calories to the nearest 10.
        - Infer the meal from wording or plausibility; use "unknown" if unclear.

        Weight rules: set weight_value and weight_unit ("lb" or "kg"; "unknown" \
        if not stated — the app applies the user's preferred unit).

        Always fill every field; use 0 / empty values for the ones that don't \
        apply. "summary" is a short, calm one-line description of what was logged.
        """

        if !corrections.isEmpty {
            let lines = corrections.prefix(10)
                .map { "- \"\($0.0)\" usually means \"\($0.1)\"" }
                .joined(separator: "\n")
            prompt += "\n\nThe user has corrected past parses. Apply these habits:\n\(lines)"
        }
        return prompt
    }

    // MARK: Schema (structured outputs)

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "kind": ["type": "string", "enum": ["food", "weight", "reflection", "distress", "target", "other"]],
            "meal": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack", "unknown"]],
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "protein_g": ["type": "number"],
                        "calories": ["type": "number"],
                    ],
                    "required": ["name", "protein_g", "calories"],
                    "additionalProperties": false,
                ],
            ],
            "weight_value": ["type": "number"],
            "weight_unit": ["type": "string", "enum": ["lb", "kg", "unknown"]],
            "reflection_tags": ["type": "array", "items": ["type": "string"]],
            "target_protein_g": ["type": "number"],
            "summary": ["type": "string"],
        ],
        "required": ["kind", "meal", "items", "weight_value", "weight_unit", "reflection_tags", "target_protein_g", "summary"],
        "additionalProperties": false,
    ]

    // MARK: Single-item macro estimate (chip fixes)

    /// When the user renames or adds a chip, re-estimate that one item so
    /// the fix corrects this log too — not just future parses.
    static func estimateMacros(for name: String) async -> (protein: Double, calories: Double) {
        if ClaudeClient.isConfigured {
            let schema: [String: Any] = [
                "type": "object",
                "properties": [
                    "protein_g": ["type": "number"],
                    "calories": ["type": "number"],
                ],
                "required": ["protein_g", "calories"],
                "additionalProperties": false,
            ]
            if let data = try? await ClaudeClient.completeJSON(
                system: "Estimate rough protein grams and calories for one food item at a typical single portion. Round protein to whole grams, calories to the nearest 10. Trends over precision.",
                user: name,
                schema: schema
            ),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let protein = (object["protein_g"] as? Double) ?? 0
                let calories = (object["calories"] as? Double) ?? 0
                return (protein, calories)
            }
        }
        return LocalFallbackParser.estimate(name: name) ?? (0, 0)
    }
}

// MARK: - On-device fallback

/// Keyword-level routing + a tiny nutrition table. Only used when Claude is
/// unreachable; the UI labels the result as a rough on-device guess.
enum LocalFallbackParser {

    /// Deliberately conservative — catches only the clearest signals so the
    /// app never replies "logged!" to them. Runs as a backstop over the
    /// Claude parse too, since routing lives on a small model.
    static func containsDistressSignals(_ raw: String) -> Bool {
        let text = raw.lowercased()
        let signals = ["kill myself", "end it all", "want to die", "hurt myself",
                       "no point in", "can't go on", "suicid", "hopeless", "worthless"]
        return signals.contains(where: text.contains)
    }

    static func parse(_ raw: String) -> ParsedEntry {
        let text = raw.lowercased()

        if containsDistressSignals(text) {
            return ParsedEntry(kind: .distress, meal: "unknown", items: [],
                               weightValue: 0, weightUnit: "unknown",
                               reflectionTags: [], targetProteinG: 0, summary: "")
        }

        // Protein target: "set my protein target to 160"
        if text.contains("target"), text.contains("protein") || text.contains("goal"),
           let match = text.firstMatch(of: /(\d{2,3})/),
           let value = Double(match.1), (40...400).contains(value) {
            return ParsedEntry(kind: .target, meal: "unknown", items: [],
                               weightValue: 0, weightUnit: "unknown",
                               reflectionTags: [], targetProteinG: value,
                               summary: "Protein target \(Int(value))g")
        }

        // Weight: a 2-3 digit number near weight-ish words, or a bare "182 this morning"
        if let value = weightValue(in: text) {
            let unit = text.contains("kg") || text.contains("kilo") ? "kg"
                     : (text.contains("lb") || text.contains("pound")) ? "lb" : "unknown"
            return ParsedEntry(kind: .weight, meal: "unknown", items: [],
                               weightValue: value, weightUnit: unit,
                               reflectionTags: [], targetProteinG: 0, summary: "Weight \(value)")
        }

        let foodish = foodTable.keys.contains(where: text.contains)
            || ["ate", "eat", "lunch", "dinner", "breakfast", "snack", "meal"].contains(where: text.contains)
        let feelish = ["stress", "anxious", "tired", "flat", "down", "overwhelm", "lonely",
                       "rough day", "exhaust", "frustrat", "angry", "upset", "feeling", "felt",
                       "mood", "burnt out", "burned out", "slept", "skipped"].contains(where: text.contains)

        if feelish && !foodish {
            var tags: [String] = []
            if text.contains("stress") { tags.append("stress") }
            if text.contains("tired") || text.contains("flat") || text.contains("exhaust") { tags.append("low energy") }
            if text.contains("skipped") { tags.append("skipped training") }
            if text.contains("slept") { tags.append(text.contains("great") || text.contains("well") ? "slept well" : "sleep") }
            return ParsedEntry(kind: .reflection, meal: "unknown", items: [],
                               weightValue: 0, weightUnit: "unknown",
                               reflectionTags: Array(tags.prefix(3)), targetProteinG: 0, summary: "Reflection")
        }

        if foodish {
            let items = foodItems(in: text)
            return ParsedEntry(kind: .food, meal: inferMeal(), items: items,
                               weightValue: 0, weightUnit: "unknown",
                               reflectionTags: [], targetProteinG: 0, summary: "Meal · rough estimate")
        }

        // Unclassifiable → keep it as a reflection so nothing is lost
        return ParsedEntry(kind: .reflection, meal: "unknown", items: [],
                           weightValue: 0, weightUnit: "unknown",
                           reflectionTags: [], targetProteinG: 0, summary: "Note")
    }

    private static func weightValue(in text: String) -> Double? {
        let weightContext = ["weigh", "weight", "lb", "pound", "kg", "kilo", "this morning", "scale"]
        guard weightContext.contains(where: text.contains) else { return nil }
        let regex = /(\d{2,3}(?:[.,]\d)?)/
        guard let match = text.firstMatch(of: regex),
              let value = Double(match.1.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return (60...400).contains(value) ? value : nil
    }

    /// Meal label from time of day — also used for one-tap "usual" re-logs
    static func inferMeal() -> String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: "breakfast"
        case 11..<15: "lunch"
        case 15..<17: "snack"
        case 17..<22: "dinner"
        default: "snack"
        }
    }

    /// Best local guess for a single renamed/added item — longest table key
    /// contained in the name wins. Nil when nothing matches.
    static func estimate(name: String) -> (Double, Double)? {
        let lowered = name.lowercased()
        let match = foodTable.keys
            .filter { lowered.contains($0) }
            .max { $0.count < $1.count }
        guard let match else { return nil }
        return foodTable[match]
    }

    private static func foodItems(in text: String) -> [ParsedFoodItem] {
        var items: [ParsedFoodItem] = []
        for (key, macro) in foodTable where text.contains(key) {
            items.append(ParsedFoodItem(name: key, proteinG: macro.0, calories: macro.1))
        }
        if items.isEmpty {
            items.append(ParsedFoodItem(name: text, proteinG: 0, calories: 0))
        }
        return items
    }

    /// name → (protein g, calories) at a typical single portion
    private static let foodTable: [String: (Double, Double)] = [
        "egg": (13, 140), "eggs": (13, 140), "toast": (3, 95), "coffee": (0, 5),
        "latte": (8, 150), "yogurt": (17, 120), "greek yogurt": (17, 120),
        "oats": (10, 300), "oatmeal": (10, 300), "banana": (1, 105), "berries": (1, 60),
        "protein shake": (30, 180), "shake": (30, 180), "chicken": (35, 280),
        "chicken bowl": (40, 620), "burrito": (25, 650), "burrito bowl": (35, 700),
        "salmon": (30, 350), "rice": (4, 210), "salad": (4, 120), "pizza": (12, 285),
        "steak": (40, 450), "pasta": (12, 400), "sandwich": (20, 400),
        "cookie": (2, 200), "bar": (10, 200), "smoothie": (10, 250), "milk": (8, 120),
    ]
}
