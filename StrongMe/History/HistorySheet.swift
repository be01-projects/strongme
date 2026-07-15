//
//  HistorySheet.swift
//  StrongMe
//
//  Correction and review, not a completion scoreboard. Days with entries
//  get a calm dot; empty days look neutral and are still tappable so
//  anything can be back-dated. Opens with today's entries already shown —
//  the day detail lives inline below the grid.
//

import SwiftData
import SwiftUI

struct HistorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var health

    @State private var monthAnchor: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var markedDays: Set<Int> = []
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            HStack {
                HStack(spacing: 8) {
                    IndigoDot()
                    EyebrowLabel(text: "History", color: Palette.indigo)
                }
                Spacer()
                monthSwitcher
            }
            .padding(.horizontal, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    weekdayHeader
                        .padding(.top, 16)
                    monthGrid
                        .padding(.top, 8)

                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(Palette.indigo).frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text("A dot means something's logged. Tap any day — even empty ones — to view, edit, or add.")
                            .font(AppFont.ui(11.5, .medium))
                            .foregroundStyle(Palette.muted)
                            .lineSpacing(3)
                    }
                    .padding(.top, 14)

                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                        .padding(.vertical, 18)

                    DayDetailSection(day: selectedDay) {
                        Task { await loadMarkers() }
                    }
                    .id(selectedDay)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
        .task(id: monthAnchor) { await loadMarkers() }
    }

    // MARK: Month navigation

    private var monthSwitcher: some View {
        HStack(spacing: 14) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                .font(AppFont.coach(17))
                .foregroundStyle(Color(hex: 0x2A2F42))

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canGoForward ? Palette.muted : Palette.hairline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthAnchor) else { return false }
        return next <= .now
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = shifted
        }
    }

    // MARK: Grid

    private var weekdayHeader: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols  // locale-aware, S M T W…
        return HStack(spacing: 5) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(AppFont.ui(11, .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let dayCount = calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthAnchor) - calendar.firstWeekday
        let leadingBlanks = (firstWeekday + 7) % 7
        let today = calendar.startOfDay(for: .now)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 44) }
            ForEach(1...dayCount, id: \.self) { dayNumber in
                let date = calendar.date(byAdding: .day, value: dayNumber - 1, to: monthAnchor)!
                let isFuture = date > today
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
                let hasEntries = markedDays.contains(dayNumber)

                Button {
                    selectedDay = calendar.startOfDay(for: date)
                } label: {
                    VStack(spacing: 3) {
                        Text("\(dayNumber)")
                            .font(AppFont.ui(14, isToday ? .semibold : .medium))
                            .foregroundStyle(
                                isToday ? .white
                                : isFuture ? Color(hex: 0xCFCDC5)
                                : hasEntries ? Palette.ink
                                : Color(hex: 0xB4B2AA)
                            )
                        Circle()
                            .fill(isToday ? .white.opacity(0.9) : Palette.indigo)
                            .frame(width: 5, height: 5)
                            .opacity(hasEntries ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isToday ? AnyShapeStyle(Palette.confirmGradient)
                                  : hasEntries ? AnyShapeStyle(Palette.surface)
                                  : AnyShapeStyle(Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isSelected && !isToday ? Palette.indigo
                                : hasEntries && !isToday ? Palette.hairline
                                : .clear,
                                lineWidth: isSelected && !isToday ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
            }
        }
    }

    // MARK: Markers

    private func loadMarkers() async {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return }
        var days = await health.healthActivityDays(in: interval)

        let start = interval.start
        let end = interval.end
        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        for entry in (try? modelContext.fetch(foodDescriptor)) ?? [] {
            days.insert(calendar.component(.day, from: entry.date))
        }
        let reflectionDescriptor = FetchDescriptor<ReflectionEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        for entry in (try? modelContext.fetch(reflectionDescriptor)) ?? [] {
            days.insert(calendar.component(.day, from: entry.date))
        }
        markedDays = days
    }
}

// MARK: - Day detail (inline)

struct DayDetailSection: View {
    let day: Date
    var onChange: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var health
    @Environment(ToastCenter.self) private var toast

    @State private var foods: [FoodEntry] = []
    @State private var reflections: [ReflectionEntry] = []
    @State private var workouts: [HealthKitService.WorkoutInfo] = []
    @State private var weights: [HealthKitService.WeightReading] = []
    @State private var captureRequest: CaptureRequest?
    @State private var loaded = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(AppFont.coach(20))
                .foregroundStyle(Color(hex: 0x2A2F42))

            if loaded && isEmpty {
                emptyState
            } else {
                ForEach(weights) { reading in
                    recordRow(icon: "⚖", title: "Weight",
                              subtitle: "\(String(format: "%.1f", reading.value)) \(reading.unitLabel) · synced")
                }
                ForEach(workouts) { workout in
                    recordRow(icon: "🏋", title: workout.name,
                              subtitle: "\(workout.minutes) min · synced")
                }
                ForEach(foods) { entry in
                    foodRow(entry)
                }
                ForEach(reflections) { entry in
                    reflectionRow(entry)
                }
            }

            Button {
                captureRequest = CaptureRequest(mode: .typing, targetDate: day)
            } label: {
                Text("＋ Add an entry").confirmButtonStyle()
            }
            .padding(.top, 4)
        }
        .task { await load() }
        .sheet(item: $captureRequest) { request in
            CaptureSheet(request: request)
                .onDisappear {
                    Task { await load() }
                    onChange()
                }
        }
    }

    private var isEmpty: Bool {
        foods.isEmpty && reflections.isEmpty && workouts.isEmpty && weights.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🌤").font(.system(size: 28)).opacity(0.55)
            Text(isToday
                 ? "Nothing logged yet today.\nSay a meal, a weight, or how it's going."
                 : "Nothing logged this day.\nAdd something whenever you like — no pressure.")
                .font(AppFont.coach(16))
                .foregroundStyle(Color(hex: 0x565B6B))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Rows

    private func recordRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            iconBox(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.ui(14, .semibold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(AppFont.ui(12, .medium))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .cardBackground(cornerRadius: 16)
    }

    private func foodRow(_ entry: FoodEntry) -> some View {
        HStack(spacing: 12) {
            iconBox("🥣")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mealLabel.capitalized == "Unknown" ? "Meal" : entry.mealLabel.capitalized)
                    .font(AppFont.ui(14, .semibold))
                    .foregroundStyle(Palette.ink)
                Text("\(entry.items.map(\.name).joined(separator: ", ")) · \(Int(entry.proteinGrams.rounded()))g")
                    .font(AppFont.ui(12, .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer()
            rowActions(
                edit: {
                    captureRequest = CaptureRequest(
                        mode: .typing,
                        prefill: entry.rawText,
                        targetDate: day,
                        replacingFoodID: entry.persistentModelID
                    )
                },
                delete: {
                    modelContext.delete(entry)
                    toast.show("Deleted")
                    Task { await load() }
                    onChange()
                }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .cardBackground(cornerRadius: 16)
    }

    private func reflectionRow(_ entry: ReflectionEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconBox("📝")
            VStack(alignment: .leading, spacing: 2) {
                Text("Reflection")
                    .font(AppFont.ui(14, .semibold))
                    .foregroundStyle(Palette.ink)
                Text("“\(entry.text)”")
                    .font(AppFont.coach(12.5))
                    .italic()
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            Spacer()
            rowActions(
                edit: {
                    captureRequest = CaptureRequest(
                        mode: .typing,
                        prefill: entry.text,
                        targetDate: day,
                        replacingReflectionID: entry.persistentModelID
                    )
                },
                delete: {
                    modelContext.delete(entry)
                    toast.show("Deleted")
                    Task { await load() }
                    onChange()
                }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .cardBackground(cornerRadius: 16)
    }

    private func iconBox(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: 16))
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xF2F1EC)))
    }

    private func rowActions(edit: @escaping () -> Void, delete: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: edit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairline))
            }
            .buttonStyle(.plain)
            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.hairline))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Data

    private func load() async {
        let interval = Calendar.current.dateInterval(of: .day, for: day)
        let start = interval?.start ?? day
        let end = interval?.end ?? day

        let foodDescriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        foods = (try? modelContext.fetch(foodDescriptor)) ?? []

        let reflectionDescriptor = FetchDescriptor<ReflectionEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        reflections = (try? modelContext.fetch(reflectionDescriptor)) ?? []

        workouts = await health.workouts(on: day)
        weights = await health.weightReadings(on: day)
        loaded = true
    }
}
