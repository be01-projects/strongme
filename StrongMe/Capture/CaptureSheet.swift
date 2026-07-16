//
//  CaptureSheet.swift
//  StrongMe
//
//  The one manual interaction: talk (or type) → parse → confirm as
//  editable chips → log. Never make the user retype.
//

import HealthKit
import SwiftData
import SwiftUI
import UIKit

// MARK: - Entry point / request

/// Everything a capture needs: how it starts, which day it logs to, and —
/// when editing from History — which entry it replaces on confirm.
struct CaptureRequest: Identifiable, Equatable {
    enum Mode: Equatable { case voice, typing }

    let id = UUID()
    var mode: Mode
    var prompt: String?
    var prefill: String?
    var targetDate: Date = .now
    var replacingFoodID: PersistentIdentifier?
    var replacingReflectionID: PersistentIdentifier?

    static func voice() -> CaptureRequest { CaptureRequest(mode: .voice) }
    static func typing(prompt: String? = nil) -> CaptureRequest { CaptureRequest(mode: .typing, prompt: prompt) }
}

// MARK: - Draft being confirmed

struct ChipItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var originalName: String
    var proteinGrams: Double
    var calories: Double
}

struct FoodDraft: Equatable {
    var meal: String
    var chips: [ChipItem]
    var rawText: String
    var source: ParseSource

    var proteinGrams: Double { chips.reduce(0) { $0 + $1.proteinGrams } }
    var calories: Double { chips.reduce(0) { $0 + $1.calories } }

    static func == (lhs: FoodDraft, rhs: FoodDraft) -> Bool { lhs.chips == rhs.chips && lhs.meal == rhs.meal }
}

// MARK: - Sheet

struct CaptureSheet: View {
    let request: CaptureRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health
    @Environment(ToastCenter.self) private var toast

    @AppStorage("proteinTargetGrams") private var proteinTarget = 150.0

    @State private var speech = SpeechRecognizer()
    @State private var phase: Phase = .idle
    @State private var typedText = ""
    @FocusState private var typingFocused: Bool

    /// Today logs at the actual moment; back-dated entries land at noon.
    private var entryDate: Date {
        if Calendar.current.isDateInToday(request.targetDate) { return .now }
        let noon = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0,
            of: request.targetDate
        )
        return noon ?? request.targetDate
    }

    enum Phase: Equatable {
        case idle
        case listening
        case typing
        case parsing
        case confirmFood(FoodDraft)
        case confirmWeight(value: Double, unit: String, raw: String)
        case confirmTarget(grams: Double)
        case confirmName(String)
        case reflectionSaved(text: String, tags: [String])
        case care
        case notice(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            String(describing: lhs) == String(describing: rhs)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
        .task { await begin() }
        .onDisappear { speech.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            ProgressView().padding(40)
        case .listening:
            listeningView
        case .typing:
            typingView
        case .parsing:
            parsingView
        case .confirmFood(let draft):
            FoodConfirmView(draft: draft, onConfirm: confirmFood, onCancel: { dismiss() })
        case .confirmWeight(let value, let unit, let raw):
            weightConfirmView(value: value, unit: unit, raw: raw)
        case .confirmTarget(let grams):
            targetConfirmView(grams: grams)
        case .confirmName(let name):
            nameConfirmView(name: name)
        case .reflectionSaved(let text, let tags):
            reflectionView(text: text, tags: tags)
        case .care:
            careView
        case .notice(let message):
            noticeView(message)
        }
    }

    // MARK: Flow

    private func begin() async {
        if let prefill = request.prefill { typedText = prefill }
        switch request.mode {
        case .voice:
            phase = .listening
            await speech.start()
            if speech.errorMessage != nil {
                phase = .typing
                return
            }
            await autoFinishWhenSilent()
        case .typing:
            phase = .typing
        }
    }

    /// Speak, pause, done — a longer pause files the entry without a tap.
    private func autoFinishWhenSilent() async {
        while phase == .listening {
            try? await Task.sleep(for: .milliseconds(250))
            guard phase == .listening else { return }
            let transcript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            // Recognizer finalized (or died) on its own
            if !speech.isListening {
                if transcript.isEmpty { phase = .typing } else { finishListening() }
                return
            }
            if !transcript.isEmpty, let lastChange = speech.lastChangeAt,
               Date.now.timeIntervalSince(lastChange) > 1.8 {
                finishListening()
                return
            }
        }
    }

    private func finishListening() {
        speech.stop()
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .typing
            return
        }
        // "I caught that" — matters most when the silence detector fired
        // and the user isn't looking at the screen
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        parse(text)
    }

    private func parse(_ text: String) {
        // "Log my usual breakfast" — smart memory beats a round trip. Only
        // when the whole utterance is the command; "log breakfast: eggs and
        // toast" still goes to the parser.
        if let meal = usualRequestMeal(in: text) {
            recallUsual(for: meal, rawText: text)
            return
        }

        phase = .parsing
        Task {
            let corrections = recentCorrections()
            let (entry, source) = await EntryParser.parse(text, corrections: corrections)
            route(entry, source: source, rawText: text)
        }
    }

    private func usualRequestMeal(in text: String) -> String? {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let pattern = /^(?:log|i (?:had|ate)|had)?\s*(?:my\s+)?(?:usual\s+)?(breakfast|lunch|dinner|snack)(?:\s+please)?$/
        guard let match = normalized.firstMatch(of: pattern) else { return nil }
        // A bare "breakfast" is ambiguous; require a verb or "usual"
        guard normalized != String(match.1) else { return nil }
        return String(match.1)
    }

    private func recallUsual(for meal: String, rawText: String) {
        let all = (try? modelContext.fetch(FetchDescriptor<UsualMeal>())) ?? []
        let candidate = all
            .filter { $0.mealLabel == meal }
            .max { ($0.timesLogged, $0.lastUsed) < ($1.timesLogged, $1.lastUsed) }
        guard let usual = candidate else {
            phase = .notice("No usual \(meal) saved yet — log it once and I'll remember it.")
            return
        }
        let chips = usual.items.map {
            ChipItem(name: $0.name, originalName: $0.name, proteinGrams: $0.proteinGrams, calories: $0.calories)
        }
        phase = .confirmFood(FoodDraft(meal: meal, chips: chips, rawText: rawText, source: .usualRecall))
    }

    private func route(_ entry: ParsedEntry, source: ParseSource, rawText: String) {
        switch entry.kind {
        case .distress:
            phase = .care

        case .food:
            let chips = entry.items.map {
                ChipItem(name: $0.name, originalName: $0.name, proteinGrams: $0.proteinG, calories: $0.calories)
            }
            phase = .confirmFood(FoodDraft(meal: entry.meal, chips: chips, rawText: rawText, source: source))

        case .weight:
            let unit = entry.weightUnit == "unknown"
                ? (health.snapshot.usesPounds ? "lb" : "kg")
                : entry.weightUnit
            phase = .confirmWeight(value: entry.weightValue, unit: unit, raw: rawText)

        case .target:
            guard entry.targetProteinG > 0 else {
                phase = .notice("I couldn't find a number in that. Try “set my protein target to 160”.")
                return
            }
            phase = .confirmTarget(grams: entry.targetProteinG)

        case .name:
            let name = entry.userName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                phase = .notice("I didn't catch the name. Try “call me Steve”.")
                return
            }
            phase = .confirmName(name)

        case .reflection, .other:
            deleteReplacedEntries()
            let reflection = ReflectionEntry(date: entryDate, text: rawText, tags: entry.reflectionTags)
            modelContext.insert(reflection)
            phase = .reflectionSaved(text: rawText, tags: entry.reflectionTags)
        }
    }

    private func confirmFood(_ draft: FoodDraft) {
        // Remember identity fixes so the parser stops guessing wrong next
        // time. Quantity-only edits ("2 eggs" → "3 eggs") aren't habits —
        // recording them would teach the parser to inflate future portions.
        // Repeat fixes refresh the existing correction instead of stacking
        // duplicates (the prompt only carries the 10 most recent).
        let existingCorrections = (try? modelContext.fetch(FetchDescriptor<FoodCorrection>())) ?? []
        for chip in draft.chips
        where chip.name != chip.originalName
            && !isQuantityOnlyChange(chip.originalName, chip.name) {
            if let existing = existingCorrections.first(where: {
                $0.original.caseInsensitiveCompare(chip.originalName) == .orderedSame
                    && $0.corrected.caseInsensitiveCompare(chip.name) == .orderedSame
            }) {
                existing.date = .now
            } else {
                modelContext.insert(FoodCorrection(original: chip.originalName, corrected: chip.name))
            }
        }

        deleteReplacedEntries()
        let items = draft.chips.map {
            FoodItemRecord(name: $0.name, proteinGrams: $0.proteinGrams, calories: $0.calories)
        }
        let entry = FoodEntry(date: entryDate, mealLabel: draft.meal, items: items, rawText: draft.rawText)
        modelContext.insert(entry)
        UsualLearner.record(items: items, meal: draft.meal, context: modelContext)

        toast.show("Logged · +\(Int(draft.proteinGrams.rounded()))g protein") { [modelContext] in
            modelContext.delete(entry)
        }
        dismiss()
    }

    private func confirmWeight(value: Double, unit: String) {
        Task {
            do {
                let sample = try await health.saveWeight(
                    value: value,
                    unit: unit == "kg" ? .gramUnit(with: .kilo) : .pound(),
                    date: entryDate
                )
                toast.show("Weight logged · \(trimmed(value)) \(unit)") { [health] in
                    Task { await health.deleteSample(sample) }
                }
                dismiss()
            } catch {
                phase = .notice("Couldn't save to Health. Check Health permissions and try again.")
            }
        }
    }

    /// "2 eggs" → "3 eggs" is the same food; "coffee" → "oat latte" isn't.
    private func isQuantityOnlyChange(_ before: String, _ after: String) -> Bool {
        func core(_ text: String) -> String {
            text.lowercased()
                .replacingOccurrences(of: #"[\d/.,½¼¾]+"#, with: "", options: .regularExpression)
                .replacingOccurrences(
                    of: #"\b(a|an|of|x|cups?|glasses?|slices?|pieces?|servings?|bowls?|halves|half|quarter|large|small|big)\b"#,
                    with: "", options: .regularExpression
                )
                .replacingOccurrences(of: " ", with: "")
        }
        return core(before) == core(after)
    }

    /// Editing from History re-logs through the same parse→confirm loop,
    /// then removes the entry being replaced.
    private func deleteReplacedEntries() {
        if let foodID = request.replacingFoodID,
           let entry = modelContext.model(for: foodID) as? FoodEntry {
            modelContext.delete(entry)
        }
        if let reflectionID = request.replacingReflectionID,
           let entry = modelContext.model(for: reflectionID) as? ReflectionEntry {
            modelContext.delete(entry)
        }
    }

    private func recentCorrections() -> [(String, String)] {
        var descriptor = FetchDescriptor<FoodCorrection>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 10
        let fixes = (try? modelContext.fetch(descriptor)) ?? []
        return fixes.map { ($0.original, $0.corrected) }
    }

    private func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: Listening

    private var listeningView: some View {
        VStack(spacing: 0) {
            ListeningOrb()
                .padding(.top, 6)

            Text(speech.isListening ? "LISTENING…" : "GOT IT")
                .font(AppFont.ui(12, .semibold))
                .kerning(1.2)
                .foregroundStyle(Palette.indigo)
                .padding(.top, 20)

            Text(speech.transcript.isEmpty ? " " : speech.transcript)
                .font(AppFont.coach(22))
                .foregroundStyle(Palette.coachInk)
                .multilineTextAlignment(.center)
                .frame(minHeight: 60)
                .frame(maxWidth: 290)
                .padding(.top, 12)

            Text("A longer pause files it — no tap needed.")
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)

            Button(action: finishListening) {
                Text("Done — that's the entry")
                    .confirmButtonStyle()
            }
            .padding(.top, 14)

            Button("Type instead") { speech.stop(); phase = .typing }
                .font(AppFont.ui(13, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 14)
        }
    }

    // MARK: Typing

    private var typingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowLabel(text: "Type anything", color: Palette.indigo)
                .padding(.bottom, 12)

            TextField(typingPlaceholder, text: $typedText, axis: .vertical)
                .font(AppFont.ui(16))
                .focused($typingFocused)
                .padding(.horizontal, 18)
                .frame(minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline))
                .submitLabel(.send)
                .onSubmit(submitTyped)
                .task {
                    // let the sheet settle before summoning the keyboard
                    try? await Task.sleep(for: .milliseconds(350))
                    typingFocused = true
                }

            Button(action: submitTyped) {
                Text("Send").confirmButtonStyle()
            }
            .padding(.top, 12)
            .disabled(typedText.trimmingCharacters(in: .whitespaces).isEmpty)

            if let error = speech.errorMessage {
                Text(error)
                    .font(AppFont.ui(12, .medium))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 12)
            }

            HStack(spacing: 9) {
                exampleChip("🍳 Eggs and toast", "two eggs, toast, and a coffee")
                exampleChip("⚖️ Weigh-in", "182 this morning")
            }
            .padding(.top, 12)
        }
    }

    private var typingPlaceholder: String {
        request.prompt ?? "food, your weight, or how your day went…"
    }

    private func submitTyped() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        parse(text)
    }

    private func exampleChip(_ label: String, _ text: String) -> some View {
        Button {
            parse(text)
        } label: {
            Text(label)
                .font(AppFont.ui(12.5, .medium))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .cardBackground(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: Parsing

    private var parsingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Filing it…")
                .font(AppFont.coach(17))
                .foregroundStyle(Palette.coachInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    // MARK: Weight confirm

    private func weightConfirmView(value: Double, unit: String, raw: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Heard you say")
                .font(AppFont.ui(12, .medium))
                .foregroundStyle(Palette.muted)
            Text("Bodyweight · filed to Health")
                .font(AppFont.coach(19))
                .foregroundStyle(Palette.ink)
                .padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(trimmed(value))
                    .font(AppFont.ui(34, .semibold))
                    .foregroundStyle(Palette.ink)
                Text(unit)
                    .font(AppFont.ui(15, .medium))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 16)

            Text("Trend over precision — one morning number is plenty.")
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Button {
                confirmWeight(value: value, unit: unit)
            } label: {
                Text("Looks right — log it").confirmButtonStyle()
            }
        }
    }

    // MARK: Target confirm

    private func targetConfirmView(grams: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Heard you say")
                .font(AppFont.ui(12, .medium))
                .foregroundStyle(Palette.muted)
            Text("Daily protein target")
                .font(AppFont.coach(19))
                .foregroundStyle(Palette.ink)
                .padding(.top, 4)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(grams))")
                    .font(AppFont.ui(34, .semibold))
                    .foregroundStyle(Palette.apricot)
                Text("g / day")
                    .font(AppFont.ui(15, .medium))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 16)

            Text("Currently \(Int(proteinTarget))g. The bar on Today and the coach both follow this.")
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Button {
                let previous = proteinTarget
                proteinTarget = grams
                toast.show("Target set · \(Int(grams))g protein") {
                    UserDefaults.standard.set(previous, forKey: "proteinTargetGrams")
                }
                dismiss()
            } label: {
                Text("Set it").confirmButtonStyle()
            }
        }
    }

    // MARK: Name confirm

    private func nameConfirmView(name: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Heard you say")
                .font(AppFont.ui(12, .medium))
                .foregroundStyle(Palette.muted)
            Text("What should I call you?")
                .font(AppFont.coach(19))
                .foregroundStyle(Palette.ink)
                .padding(.top, 4)

            Text(name)
                .font(AppFont.coach(30, .medium))
                .foregroundStyle(Palette.indigo)
                .padding(.top, 16)

            Text("Just for the greeting — it never leaves the device.")
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Button {
                let previous = UserDefaults.standard.string(forKey: "userName") ?? ""
                UserDefaults.standard.set(name, forKey: "userName")
                toast.show("Nice to meet you, \(name)") {
                    UserDefaults.standard.set(previous, forKey: "userName")
                }
                dismiss()
            } label: {
                Text("That's me").confirmButtonStyle()
            }
        }
    }

    // MARK: Reflection saved

    private func reflectionView(text: String, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Saved as a reflection")
                .font(AppFont.ui(12, .medium))
                .foregroundStyle(Palette.muted)
            Text("Kept in your words — not scored")
                .font(AppFont.coach(19))
                .foregroundStyle(Palette.indigo)
                .padding(.top, 4)

            Text("“\(text)”")
                .font(AppFont.coach(18))
                .foregroundStyle(Palette.coachInk)
                .lineSpacing(4)
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground(cornerRadius: 16)
                .padding(.top, 12)

            if !tags.isEmpty {
                FlowChips(tags: tags)
                    .padding(.top, 12)
            }

            Text("Added as context for your coach, so it can connect how you feel to what your body's doing. Never turned into a score.")
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 12)
                .padding(.bottom, 18)

            Button { dismiss() } label: {
                Text("Done").confirmButtonStyle()
            }
        }
    }

    // MARK: Care / distress

    private var careView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                Circle()
                    .fill(.white)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(Palette.careHeart)
                    )
                    .cardShadow()

                Text("That sounds really heavy — I'm glad you put it into words. This isn't something to log or fix with a number, and you don't have to carry it on your own.")
                    .font(AppFont.coach(17))
                    .foregroundStyle(Palette.coachInk)
                    .lineSpacing(4)

                Text("Talking to someone you trust, or a mental health professional, can genuinely help. In the U.S. you can call or text 988 (Suicide & Crisis Lifeline) any time; elsewhere, findahelpline.com lists local support.")
                    .font(AppFont.ui(13.5, .medium))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.careGradient))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.careBorder))
            .padding(.bottom, 14)

            Button { dismiss() } label: {
                Text("Okay").confirmButtonStyle()
            }
        }
    }

    // MARK: Notice

    private func noticeView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(AppFont.coach(17))
                .foregroundStyle(Palette.coachInk)
            Button { dismiss() } label: {
                Text("Okay").confirmButtonStyle()
            }
        }
    }
}

// MARK: - Food confirm subview

private struct FoodConfirmView: View {
    @State var draft: FoodDraft
    let onConfirm: (FoodDraft) -> Void
    let onCancel: () -> Void

    @State private var editingChip: ChipItem?
    @State private var editText = ""
    @State private var addingItem = false
    @State private var addText = ""
    @State private var estimatingChipIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Heard you say")
                .font(AppFont.ui(12, .medium))
                .foregroundStyle(Palette.muted)
            // The meal label is a guess too — tap to fix it like a chip
            Menu {
                ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { meal in
                    Button(meal.capitalized) { draft.meal = meal }
                }
            } label: {
                HStack(spacing: 5) {
                    Text("\(draft.meal.capitalized == "Unknown" ? "Meal" : draft.meal.capitalized) · logged to food")
                        .font(AppFont.coach(19))
                        .foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.indigo)
                }
            }
            .padding(.top, 2)
            Text(macroLine)
                .font(AppFont.ui(13, .semibold))
                .foregroundStyle(Palette.apricot)
                .padding(.top, 2)
                .padding(.bottom, 16)

            chipGrid

            Text(editNote)
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Button {
                onConfirm(draft)
            } label: {
                Text("Looks right — log it").confirmButtonStyle()
            }
            .disabled(draft.chips.isEmpty)
        }
        .alert("Fix this item", isPresented: Binding(
            get: { editingChip != nil },
            set: { if !$0 { editingChip = nil } }
        )) {
            TextField("Item", text: $editText)
            Button("Save") {
                if let chip = editingChip,
                   let index = draft.chips.firstIndex(where: { $0.id == chip.id }) {
                    let name = editText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, name != chip.name {
                        draft.chips[index].name = name
                        reestimate(chipID: chip.id, name: name)
                    }
                }
                editingChip = nil
            }
            Button("Cancel", role: .cancel) { editingChip = nil }
        } message: {
            Text("Macros re-estimate for this log, and the correction is remembered for future parses.")
        }
        .alert("Add an item", isPresented: $addingItem) {
            TextField("e.g. a cookie", text: $addText)
            Button("Add") {
                let name = addText.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let chip = ChipItem(name: name, originalName: name, proteinGrams: 0, calories: 0)
                draft.chips.append(chip)
                reestimate(chipID: chip.id, name: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything the parse missed.")
        }
    }

    /// Fix the macros for this log too — not just future parses.
    private func reestimate(chipID: UUID, name: String) {
        estimatingChipIDs.insert(chipID)
        Task {
            let (protein, calories) = await EntryParser.estimateMacros(for: name)
            if let index = draft.chips.firstIndex(where: { $0.id == chipID }) {
                draft.chips[index].proteinGrams = protein
                draft.chips[index].calories = calories
            }
            estimatingChipIDs.remove(chipID)
        }
    }

    private var macroLine: String {
        estimatingChipIDs.isEmpty
            ? "≈ \(Int(draft.calories.rounded())) kcal · \(Int(draft.proteinGrams.rounded()))g protein"
            : "≈ updating estimate…"
    }

    private var editNote: String {
        switch draft.source {
        case .onDeviceFallback:
            "Rough on-device guess (no API key set) — tap a chip to fix it, × to remove, ＋ if something's missing."
        case .usualRecall:
            "Your usual — tweak anything before logging, or just confirm."
        case .claude:
            "Tap a chip to fix it, × to remove, ＋ if something's missing — it remembers your corrections next time."
        }
    }

    private var chipGrid: some View {
        FlowLayout(spacing: 9) {
            ForEach(draft.chips) { chip in
                HStack(spacing: 9) {
                    Text(chip.name)
                        .font(AppFont.ui(14, .medium))
                        .foregroundStyle(Palette.ink)
                        .opacity(estimatingChipIDs.contains(chip.id) ? 0.4 : 1)
                    Button {
                        draft.chips.removeAll { $0.id == chip.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 19, height: 19)
                            .background(Circle().fill(Color(hex: 0xEFEDE7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(chip.name)")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .cardBackground(cornerRadius: 14)
                .onTapGesture {
                    editText = chip.name
                    editingChip = chip
                }
            }

            Button {
                addText = ""
                addingItem = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("add")
                        .font(AppFont.ui(14, .medium))
                }
                .foregroundStyle(Palette.indigo)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: 0xDADCE8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Shared pieces

private struct ListeningOrb: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<2) { index in
                Circle()
                    .stroke(Palette.indigo.opacity(0.35), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.9 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(Double(index) * 1.05),
                        value: pulse
                    )
            }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x8B98D2), Palette.indigo],
                        center: .init(x: 0.38, y: 0.34),
                        startRadius: 4, endRadius: 70
                    )
                )
                .frame(width: 96, height: 96)
                .shadow(color: Palette.indigo.opacity(0.4), radius: 15, y: 10)
        }
        .onAppear { pulse = true }
    }
}

struct FlowChips: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 9) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(AppFont.ui(12.5, .semibold))
                    .foregroundStyle(Palette.indigo)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF4F5FA)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0xDADCE8)))
            }
        }
    }
}

extension Text {
    /// The indigo-gradient primary action button used across sheets
    func confirmButtonStyle() -> some View {
        self
            .font(AppFont.ui(15.5, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.confirmGradient))
            .shadow(color: Palette.indigo.opacity(0.3), radius: 10, y: 8)
    }
}

// MARK: - Minimal flow layout for chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}

// MARK: - "Usual" learning

enum UsualLearner {
    /// Confirmed meals become one-tap usuals; frequency wins over the seeds.
    static func record(items: [FoodItemRecord], meal: String, context: ModelContext) {
        let name = displayName(for: items)
        let all = (try? context.fetch(FetchDescriptor<UsualMeal>())) ?? []
        if let existing = all.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            existing.timesLogged += 1
            existing.lastUsed = .now
            existing.items = items
            existing.isSeed = false
            if meal != "unknown" { existing.mealLabel = meal }  // recency wins
        } else {
            context.insert(UsualMeal(name: name, items: items, timesLogged: 1, mealLabel: meal))
        }
    }

    private static func displayName(for items: [FoodItemRecord]) -> String {
        let names = items.prefix(2).map { shorten($0.name) }
        var name = names.joined(separator: " + ")
        if items.count > 2 { name += " +" }
        return name
    }

    private static func shorten(_ name: String) -> String {
        let words = name.split(separator: " ")
        return words.count <= 3 ? name : words.prefix(3).joined(separator: " ")
    }
}
