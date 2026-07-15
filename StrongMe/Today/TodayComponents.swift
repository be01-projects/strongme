//
//  TodayComponents.swift
//  StrongMe
//
//  The at-a-glance grid, protein bar, and talk dock from the prototype.
//

import SwiftUI

// MARK: - 2×2 at-a-glance grid (all Tier 0 / auto)

struct StatGrid: View {
    let snapshot: HealthSnapshot
    /// Every card is a door: tapping one opens that metric's recent history
    var onOpen: (Metric) -> Void = { _ in }

    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 11) {
            card(.steps) {
                StatCard(icon: .ring, label: "Steps", value: stepsValue, valueSuffix: nil, sub: stepsSub)
            }
            card(.sleep) {
                StatCard(icon: .emoji("🌙"), label: "Sleep", value: sleepValue, valueSuffix: nil, sub: sleepSub)
            }
            card(.training) {
                StatCard(icon: .emoji("🏋"), label: "Training", value: "\(snapshot.workoutsThisWeek)",
                         valueSuffix: " this week", sub: trainingSub, subHighlighted: snapshot.workoutsThisWeek >= 3)
            }
            card(.weight) {
                StatCard(icon: .emoji("⚖"), label: "Weight", value: weightValue,
                         valueSuffix: snapshot.latestWeight != nil ? snapshot.weightUnitLabel : nil,
                         sub: weightSub, subHighlighted: (snapshot.weightChangeTwoWeeks ?? 0) < 0)
            }
        }
    }

    private func card(_ metric: Metric, @ViewBuilder content: () -> some View) -> some View {
        Button {
            onOpen(metric)
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    // Steps
    private var stepsValue: String {
        guard let steps = snapshot.stepsToday else { return "—" }
        return steps.formatted(.number.grouping(.automatic))
    }
    private var stepsSub: String {
        guard let steps = snapshot.stepsToday, let avg = snapshot.stepsDailyAverage, avg > 0 else {
            return "No data yet"
        }
        return "\(Int((Double(steps) / Double(avg) * 100).rounded()))% of your average day"
    }

    // Sleep
    private var sleepValue: String {
        guard let sleep = snapshot.sleepLastNight else { return "—" }
        let hours = Int(sleep) / 3600
        let minutes = (Int(sleep) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    private var sleepSub: String {
        guard let sleep = snapshot.sleepLastNight else { return "No data yet" }
        switch sleep {
        case ..<(6 * 3600): return "A short night — go easy"
        case ..<(7 * 3600): return "A little light"
        case ..<(9 * 3600): return "Solid — right on trend"
        default: return "Well rested"
        }
    }

    // Training
    private var trainingSub: String {
        if snapshot.trainedToday { return "Trained today — nice" }
        if snapshot.workoutsThisWeek >= 3 { return "Nice rhythm going" }
        if snapshot.workoutsThisWeek > 0 { return "Building the week" }
        return "A fresh week"
    }

    // Weight
    private var weightValue: String {
        guard let weight = snapshot.latestWeight else { return "—" }
        return weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(format: "%.1f", weight)
    }
    private var weightSub: String {
        guard snapshot.latestWeight != nil else { return "Say it: “182 this morning”" }
        guard let change = snapshot.weightChangeTwoWeeks, abs(change) >= 0.2 else { return "Holding steady" }
        let arrow = change < 0 ? "↓" : "↑"
        return "\(arrow) \(String(format: "%.1f", abs(change))) over 2 weeks"
    }
}

struct StatCard: View {
    enum Icon {
        case ring
        case emoji(String)
    }

    let icon: Icon
    let label: String
    let value: String
    var valueSuffix: String?
    let sub: String
    var subHighlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                iconView
                EyebrowLabel(text: label)
                Spacer()
                Text("AUTO")
                    .font(AppFont.ui(10, .semibold))
                    .kerning(0.4)
                    .foregroundStyle(Color(hex: 0xA9AAB2))
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppFont.ui(25, .semibold))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                if let valueSuffix {
                    Text(valueSuffix)
                        .font(AppFont.ui(13, .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.top, 9)

            Text(sub)
                .font(AppFont.ui(12, .medium))
                .foregroundStyle(subHighlighted ? Palette.indigo : Palette.muted)
                .lineLimit(1)
                .padding(.top, 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .ring:
            Circle()
                .trim(from: 0, to: 0.55)
                .stroke(Palette.indigoLight, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .background(
                    Circle().stroke(Color(hex: 0xE1E3EE), lineWidth: 3)
                )
                .rotationEffect(.degrees(45))
                .frame(width: 13, height: 13)
        case .emoji(let symbol):
            Text(symbol).font(.system(size: 12))
        }
    }
}

// MARK: - Protein bar (the one warm signal)

struct ProteinCard: View {
    let proteinToday: Double
    let target: Double

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, proteinToday / target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowLabel(text: "Protein")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(Int(proteinToday.rounded()))")
                        .font(AppFont.ui(15, .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(" / \(Int(target))g")
                        .font(AppFont.ui(15, .medium))
                        .foregroundStyle(Palette.muted)
                }
                .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEFEDE7))
                    Capsule()
                        .fill(Palette.proteinGradient)
                        .frame(width: max(11, geometry.size.width * progress))
                        .animation(.spring(duration: 0.9), value: progress)
                }
            }
            .frame(height: 11)
            .padding(.top, 12)

            Text(hint)
                .font(AppFont.ui(11.5, .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 9)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var hint: String {
        let remaining = target - proteinToday
        if proteinToday <= 0 { return "The one number worth watching. Say a meal to start." }
        if remaining <= 0 { return "Target hit. Nicely done." }
        if remaining <= 35 { return "\(Int(remaining.rounded()))g to go — one solid meal closes it." }
        return "\(Int(remaining.rounded()))g to go — you're on it."
    }
}

// MARK: - Talk dock

struct TalkDock: View {
    let onTalk: () -> Void
    let onType: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button(action: onTalk) {
                HStack(spacing: 11) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                    Text("Tap to talk")
                        .font(AppFont.ui(15.5, .semibold))
                    WaveBars()
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.talkGradient))
                .shadow(color: Palette.indigo.opacity(0.34), radius: 11, y: 8)
            }
            .buttonStyle(.plain)

            Button(action: onType) {
                Image(systemName: "keyboard")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 60, height: 60)
                    .cardBackground(cornerRadius: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Palette.app.opacity(0), Palette.app, Palette.app],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// The little animated equalizer inside the talk button
private struct WaveBars: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: animating ? 17 : 6)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: 20)
        .onAppear { animating = true }
    }
}
