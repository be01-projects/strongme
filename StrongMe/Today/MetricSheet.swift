//
//  MetricSheet.swift
//  StrongMe
//
//  Tapping a stat card opens the last two weeks of that metric — calm
//  rows and bars, direction over decimal points, never a raw table.
//  The coach stays one tap away at the bottom.
//

import SwiftUI

enum Metric: String, Identifiable {
    case steps, sleep, training, weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .training: "Training"
        case .weight: "Weight"
        }
    }

    var coachQuestion: String {
        switch self {
        case .steps: "How are my steps looking lately?"
        case .sleep: "How's my sleep been?"
        case .training: "How's my training rhythm?"
        case .weight: "How's my weight trending?"
        }
    }
}

struct MetricSheet: View {
    let metric: Metric

    @Environment(HealthKitService.self) private var health

    @State private var steps: [(day: Date, steps: Int)] = []
    @State private var nights: [(night: Date, duration: TimeInterval)] = []
    @State private var workouts: [HealthKitService.WorkoutInfo] = []
    @State private var weights: [HealthKitService.WeightReading] = []
    @State private var loaded = false
    @State private var showCoach = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            HStack(spacing: 8) {
                IndigoDot()
                EyebrowLabel(text: "\(metric.title) · last 2 weeks", color: Palette.indigo)
                Spacer()
                Text("AUTO")
                    .font(AppFont.ui(10, .semibold))
                    .kerning(0.4)
                    .foregroundStyle(Color(hex: 0xA9AAB2))
            }
            .padding(.horizontal, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !loaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if isEmpty {
                        emptyState
                    } else {
                        content
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
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
        .task { await load() }
        .sheet(isPresented: $showCoach) {
            CoachSheet(initialQuestion: metric.coachQuestion)
        }
    }

    private var isEmpty: Bool {
        switch metric {
        case .steps: steps.isEmpty
        case .sleep: nights.isEmpty
        case .training: workouts.isEmpty
        case .weight: weights.isEmpty
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🌤").font(.system(size: 28)).opacity(0.55)
            Text(metric == .weight
                 ? "No readings yet.\nSay it once a morning: “182 this morning.”"
                 : "Nothing here yet.\nThis syncs from Apple Health on its own.")
                .font(AppFont.coach(16))
                .foregroundStyle(Color(hex: 0x565B6B))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Per-metric content

    @ViewBuilder
    private var content: some View {
        switch metric {
        case .steps:
            let maxSteps = max(steps.map(\.steps).max() ?? 1, 1)
            ForEach(steps.reversed(), id: \.day) { entry in
                barRow(
                    label: dayLabel(entry.day),
                    fraction: Double(entry.steps) / Double(maxSteps),
                    value: entry.steps.formatted(.number.grouping(.automatic))
                )
            }

        case .sleep:
            let maxSleep = max(nights.map(\.duration).max() ?? 1, 1)
            ForEach(nights.reversed(), id: \.night) { entry in
                barRow(
                    label: dayLabel(entry.night),
                    fraction: entry.duration / maxSleep,
                    value: hoursMinutes(entry.duration)
                )
            }

        case .training:
            ForEach(workouts) { workout in
                HStack(spacing: 12) {
                    Text("🏋")
                        .font(.system(size: 15))
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0xF2F1EC)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name)
                            .font(AppFont.ui(14, .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("\(workout.minutes) min")
                            .font(AppFont.ui(12, .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Text(dayLabel(workout.start))
                        .font(AppFont.ui(11, .semibold))
                        .kerning(0.3)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .cardBackground(cornerRadius: 14)
            }

        case .weight:
            // newest first; delta vs the previous (older) reading
            ForEach(Array(weights.enumerated()), id: \.element.id) { index, reading in
                HStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", reading.value))
                            .font(AppFont.ui(17, .semibold))
                            .foregroundStyle(Palette.ink)
                            .monospacedDigit()
                        Text(reading.unitLabel)
                            .font(AppFont.ui(12, .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    if index + 1 < weights.count {
                        let delta = reading.value - weights[index + 1].value
                        if abs(delta) >= 0.1 {
                            Text("\(delta < 0 ? "↓" : "↑") \(String(format: "%.1f", abs(delta)))")
                                .font(AppFont.ui(12, .semibold))
                                .foregroundStyle(delta < 0 ? Palette.indigo : Palette.muted)
                        }
                    }
                    Spacer()
                    Text(dayLabel(reading.date))
                        .font(AppFont.ui(11, .semibold))
                        .kerning(0.3)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .cardBackground(cornerRadius: 14)
            }
        }
    }

    private func barRow(label: String, fraction: Double, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(AppFont.ui(11, .semibold))
                .kerning(0.3)
                .foregroundStyle(Palette.muted)
                .frame(width: 58, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEFEDE7))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.indigoLight.opacity(0.7), Palette.indigo],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geometry.size.width * fraction))
                }
            }
            .frame(height: 9)
            Text(value)
                .font(AppFont.ui(12, .semibold))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    // MARK: Helpers

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YDAY" }
        return date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()
    }

    private func hoursMinutes(_ interval: TimeInterval) -> String {
        "\(Int(interval) / 3600)h \((Int(interval) % 3600) / 60)m"
    }

    private func load() async {
        switch metric {
        case .steps: steps = await health.dailySteps(lastDays: 14)
        case .sleep: nights = await health.nightlySleep(lastNights: 14)
        case .training: workouts = await health.workoutHistory(lastDays: 14)
        case .weight: weights = await health.weightHistory(lastDays: 14)
        }
        loaded = true
    }
}
