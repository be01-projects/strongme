//
//  ProteinSheet.swift
//  StrongMe
//
//  Tapping the protein bar answers "what have I eaten today?" — today's
//  meals with their protein, editable in place, then the week's direction.
//

import SwiftData
import SwiftUI

struct ProteinSheet: View {
    /// Passed by TodayContent so the sheet and the screen behind it always
    /// agree on what "today" is (the sheet has no rollover machinery of its own)
    let dayStart: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toast

    @AppStorage("proteinTargetGrams") private var proteinTarget = 150.0

    /// One live query over the whole week — today's list and the bars both
    /// derive from it, so every write (including a Siri log landing while
    /// the sheet is open) updates both halves together.
    @Query private var weekFood: [FoodEntry]
    @State private var captureRequest: CaptureRequest?
    @State private var showCoach = false

    init(dayStart: Date) {
        self.dayStart = dayStart
        let weekAgo = Calendar.current.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        _weekFood = Query(filter: #Predicate<FoodEntry> { $0.date >= weekAgo },
                          sort: \.date)
    }

    private var todaysFood: [FoodEntry] { weekFood.filter { $0.date >= dayStart } }

    private var weekTotals: [(day: Date, grams: Double)] {
        let calendar = Calendar.current
        var byDay: [Date: Double] = [:]
        for entry in weekFood {
            byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.proteinGrams
        }
        return byDay.keys.sorted().map { ($0, byDay[$0]!) }
    }

    private var proteinToday: Double { todaysFood.reduce(0) { $0 + $1.proteinGrams } }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                IndigoDot()
                EyebrowLabel(text: "Protein · today", color: Palette.indigo)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int(proteinToday.rounded()))")
                        .font(AppFont.ui(15, .semibold))
                        .foregroundStyle(Palette.apricot)
                    Text(" / \(Int(proteinTarget))g")
                        .font(AppFont.ui(15, .medium))
                        .foregroundStyle(Palette.muted)
                }
                .monospacedDigit()
            }
            .padding(.horizontal, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if todaysFood.isEmpty {
                        emptyState
                    } else {
                        ForEach(todaysFood) { entry in
                            mealRow(entry)
                        }
                    }

                    Button {
                        captureRequest = .typing()
                    } label: {
                        Text("＋ Log a meal").confirmButtonStyle()
                    }
                    .padding(.top, 4)

                    if weekTotals.count > 1 {
                        EyebrowLabel(text: "Last 7 days")
                            .padding(.top, 18)
                        weekBars
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            Button {
                showCoach = true
            } label: {
                HStack(spacing: 6) {
                    Text("Ask your coach")
                        .font(AppFont.ui(15.5, .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.confirmGradient))
                .shadow(color: Palette.indigo.opacity(0.3), radius: 10, y: 8)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
        .sheet(item: $captureRequest) { request in
            CaptureSheet(request: request)
        }
        .sheet(isPresented: $showCoach) {
            CoachSheet(initialQuestion: "Am I on track with protein?")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🌤").font(.system(size: 28)).opacity(0.55)
            Text("Nothing logged yet today.\nSay a meal — one sentence is enough.")
                .font(AppFont.coach(16))
                .foregroundStyle(Color(hex: 0x565B6B))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Meal rows (edit and delete in place)

    private func mealRow(_ entry: FoodEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.mealLabel.capitalized == "Unknown" ? "Meal" : entry.mealLabel.capitalized)
                        .font(AppFont.ui(14, .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(entry.date.formatted(.dateTime.hour().minute()))
                        .font(AppFont.ui(11, .medium))
                        .foregroundStyle(Palette.muted)
                }
                Text(entry.items.map(\.name).joined(separator: ", "))
                    .font(AppFont.ui(12, .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            Spacer()
            Text("+\(Int(entry.proteinGrams.rounded()))g")
                .font(AppFont.ui(14, .bold))
                .foregroundStyle(Palette.apricot)
                .monospacedDigit()

            HStack(spacing: 6) {
                Button {
                    captureRequest = CaptureRequest(
                        mode: .typing,
                        prefill: entry.rawText,
                        replacingFoodID: entry.persistentModelID
                    )
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit meal")

                Button {
                    let (date, meal, items, raw) = (entry.date, entry.mealLabel, entry.items, entry.rawText)
                    modelContext.delete(entry)
                    toast.show("Deleted") { [modelContext] in
                        modelContext.insert(FoodEntry(date: date, mealLabel: meal, items: items, rawText: raw))
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete meal")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .cardBackground(cornerRadius: 16)
    }

    // MARK: Week bars

    private var weekBars: some View {
        let maxGrams = max(weekTotals.map(\.grams).max() ?? 1, proteinTarget)
        return VStack(spacing: 4) {
            ForEach(weekTotals.reversed(), id: \.day) { entry in
                HStack(spacing: 10) {
                    Text(dayLabel(entry.day))
                        .font(AppFont.ui(11, .semibold))
                        .kerning(0.3)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 58, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0xEFEDE7))
                            // target tick
                            Rectangle()
                                .fill(Palette.muted.opacity(0.35))
                                .frame(width: 1.5)
                                .offset(x: geometry.size.width * (proteinTarget / maxGrams))
                            Capsule()
                                .fill(Palette.proteinGradient)
                                .frame(width: max(8, geometry.size.width * (entry.grams / maxGrams)))
                        }
                    }
                    .frame(height: 9)
                    Text("\(Int(entry.grams.rounded()))g")
                        .font(AppFont.ui(12, .semibold))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YDAY" }
        return date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()
    }

}
