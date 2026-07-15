//
//  TodayView.swift
//  StrongMe
//
//  Home, 90% of usage. Everything Health already knows renders itself;
//  the talk dock is the one way in for everything else.
//

import SwiftData
import SwiftUI

// MARK: - Toast

@Observable
final class ToastCenter {
    private(set) var message: String?
    private(set) var undoAction: (() -> Void)?
    private var hideTask: Task<Void, Never>?

    /// Forgiveness in one tap: pass `undo` and the toast carries an Undo
    /// button (and lingers a little longer).
    func show(_ text: String, undo: (() -> Void)? = nil) {
        hideTask?.cancel()
        undoAction = undo
        withAnimation(.spring(duration: 0.32)) { message = text }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(undo == nil ? 2.1 : 4.5))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.32)) { self.message = nil }
            self.undoAction = nil
        }
    }

    func performUndo() {
        let action = undoAction
        undoAction = nil
        hideTask?.cancel()
        withAnimation(.spring(duration: 0.32)) { message = nil }
        action?()
        show("Undone")
    }
}

// MARK: - Today

/// Thin wrapper that owns "which day is today": rebuilds the content (and
/// its day-anchored queries) at day rollover, and refreshes Health data
/// whenever the app returns to the foreground.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthKitService.self) private var health

    @State private var dayStart = Calendar.current.startOfDay(for: .now)

    var body: some View {
        TodayContent(dayStart: dayStart)
            .id(dayStart)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let today = Calendar.current.startOfDay(for: .now)
                if today != dayStart { dayStart = today }
                Task { await health.refresh() }
            }
    }
}

struct TodayContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var health
    @Environment(ToastCenter.self) private var toast

    @Query private var todaysFood: [FoodEntry]
    @Query(sort: [SortDescriptor(\UsualMeal.timesLogged, order: .reverse),
                  SortDescriptor(\UsualMeal.lastUsed, order: .reverse)])
    private var usuals: [UsualMeal]
    @Query(sort: \ReflectionEntry.date, order: .reverse) private var reflections: [ReflectionEntry]

    @AppStorage("proteinTargetGrams") private var proteinTarget = 150.0
    @AppStorage("firstLaunchDate") private var firstLaunchTimestamp = 0.0
    // Claude-written daily read; the stamp tracks day + data state so the
    // read regenerates after new logs instead of going stale
    @AppStorage("dailyInsightText") private var dailyInsightText = ""
    @AppStorage("dailyInsightStamp") private var dailyInsightStamp = ""

    @State private var captureRequest: CaptureRequest?
    @State private var showCoach = false
    @State private var showHistory = false
    @State private var openMetric: Metric?

    let dayStart: Date

    init(dayStart: Date) {
        self.dayStart = dayStart
        _todaysFood = Query(filter: #Predicate<FoodEntry> { $0.date >= dayStart },
                            sort: \.date, order: .reverse)
    }

    private var proteinToday: Double { todaysFood.reduce(0) { $0 + $1.proteinGrams } }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    insightCard
                        .padding(.top, 20)
                    StatGrid(snapshot: health.snapshot) { metric in
                        openMetric = metric
                    }
                    .padding(.top, 16)
                    Button {
                        showHistory = true  // opens on today's entries — edit from there
                    } label: {
                        ProteinCard(proteinToday: proteinToday, target: proteinTarget)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 11)
                    usualRow
                        .padding(.top, 22)
                    reflectionSection
                        .padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 150)
            }
            .scrollIndicators(.hidden)

            TalkDock(
                onTalk: { captureRequest = .voice() },
                onType: { captureRequest = .typing() }
            )

            if let message = toast.message {
                ToastView(message: message, onUndo: toast.undoAction != nil ? { toast.performUndo() } : nil)
                    .padding(.bottom, 118)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Palette.app)
        .sheet(item: $captureRequest) { request in
            CaptureSheet(request: request)
        }
        .sheet(isPresented: $showCoach) {
            CoachSheet()
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet()
        }
        .sheet(item: $openMetric) { metric in
            MetricSheet(metric: metric)
        }
        .task {
            if firstLaunchTimestamp == 0 { firstLaunchTimestamp = Date.now.timeIntervalSince1970 }
            #if DEBUG
            // Scripted screenshots / UI tests
            if ProcessInfo.processInfo.arguments.contains("-open-coach") { showCoach = true }
            if ProcessInfo.processInfo.arguments.contains("-open-history") { showHistory = true }
            if let metricArg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-open-metric-") }),
               let metric = Metric(rawValue: String(metricArg.dropFirst("-open-metric-".count))) {
                openMetric = metric
            }
            #endif
            await health.requestAuthorization()
            await health.refresh()
            await refreshDailyInsight()
        }
        .onChange(of: captureRequest) { _, newValue in
            if newValue == nil {
                Task {
                    await health.refresh()
                    await refreshDailyInsight()
                }
            }
        }
        .sensoryFeedback(.success, trigger: toast.message) { _, newValue in
            newValue != nil
        }
    }

    /// Day + data state — when either changes, the read regenerates.
    private var insightStamp: String {
        let day = Date.now.formatted(.iso8601.year().month().day())
        let weight = Int(health.snapshot.latestWeight ?? 0)
        return "\(day)|\(todaysFood.count)|\(weight)|\(Int(proteinTarget))"
    }

    private func refreshDailyInsight() async {
        guard dailyInsightStamp != insightStamp, ClaudeClient.isConfigured else { return }
        let stamp = insightStamp
        let summary = await TrendSummary.build(
            context: modelContext, health: health, proteinTarget: proteinTarget
        )
        if let insight = await DailyInsight.generate(summary: summary) {
            dailyInsightText = insight
            dailyInsightStamp = stamp
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(AppFont.coach(30, .medium))
                    .foregroundStyle(Palette.ink)
                Text(dateLine)
                    .font(AppFont.ui(13.5, .medium))
                    .kerning(0.15)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                showHistory = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 42, height: 42)
                    .cardBackground(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.top, 14)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<12: "Good morning."
        case 12..<17: "Good afternoon."
        default: "Good evening."
        }
    }

    private var dateLine: String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard firstLaunchTimestamp > 0 else { return date }
        let first = Date(timeIntervalSince1970: firstLaunchTimestamp)
        let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: first),
                                                    to: Calendar.current.startOfDay(for: .now)).day ?? 0) + 1
        return "\(date) · Day \(days)"
    }

    // MARK: Insight

    private var insightText: String {
        // Any cached read from today is better than the rule-based fallback,
        // even mid-regeneration after a new log
        let todayKey = Date.now.formatted(.iso8601.year().month().day())
        if dailyInsightStamp.hasPrefix(todayKey), !dailyInsightText.isEmpty {
            return dailyInsightText
        }
        return InsightEngine.dailyRead(
            snapshot: health.snapshot,
            proteinToday: proteinToday,
            proteinTarget: proteinTarget,
            hasLoggedFoodToday: !todaysFood.isEmpty
        )
    }

    private var insightCard: some View {
        Button {
            showCoach = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    IndigoDot()
                    EyebrowLabel(text: "Today's read", color: Palette.indigo)
                }
                Text(markdown(insightText))
                    .font(AppFont.coach(18.5))
                    .foregroundStyle(Palette.coachInk)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Text("Ask your coach")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(AppFont.ui(12.5, .semibold))
                .foregroundStyle(Palette.indigo)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.insightGradient))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.insightBorder))
        }
        .buttonStyle(.plain)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    // MARK: Usuals

    private var usualRow: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                EyebrowLabel(text: "Your usual · one tap")
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(usuals.prefix(6)) { usual in
                        Button {
                            quickLog(usual)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(usual.name)
                                    .font(AppFont.ui(13.5, .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text("+\(Int(usual.proteinGrams.rounded()))g protein")
                                    .font(AppFont.ui(11.5, .semibold))
                                    .foregroundStyle(Palette.apricot)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(minWidth: 112, alignment: .leading)
                            .cardBackground(cornerRadius: 15)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func quickLog(_ usual: UsualMeal) {
        let entry = FoodEntry(mealLabel: LocalFallbackParser.inferMeal(),
                              items: usual.items,
                              rawText: usual.name)
        modelContext.insert(entry)
        usual.timesLogged += 1
        usual.lastUsed = .now
        usual.isSeed = false
        toast.show("Logged · +\(Int(usual.proteinGrams.rounded()))g protein") { [modelContext] in
            modelContext.delete(entry)
            usual.timesLogged = max(0, usual.timesLogged - 1)
        }
    }

    // MARK: Reflection

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button {
                captureRequest = .typing(prompt: "How are you feeling? What kind of day was it?")
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel(text: "Reflection", color: Palette.indigo)
                        Text("How's today feeling?")
                            .font(AppFont.coach(18))
                            .foregroundStyle(Palette.coachInk)
                    }
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.indigo)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.white))
                        .cardShadow()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.insightGradient))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.insightBorder))
            }
            .buttonStyle(.plain)

            ForEach(reflections.prefix(2)) { entry in
                Button {
                    captureRequest = CaptureRequest(
                        mode: .typing,
                        prefill: entry.text,
                        targetDate: entry.date,
                        replacingReflectionID: entry.persistentModelID
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 11) {
                        Text(relativeDay(entry.date))
                            .font(AppFont.ui(10.5, .bold))
                            .kerning(0.4)
                            .foregroundStyle(Palette.muted)
                            .frame(minWidth: 56, alignment: .leading)
                        Text("“\(entry.text)”")
                            .font(AppFont.coach(13.5))
                            .italic()
                            .foregroundStyle(Color(hex: 0x3A3F52))
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.muted.opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        return date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }
}

// MARK: - Toast view

struct ToastView: View {
    let message: String
    var onUndo: (() -> Void)?

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Palette.apricot)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text(message)
                .font(AppFont.ui(13.5, .semibold))
                .foregroundStyle(.white)

            if let onUndo {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1, height: 16)
                Button(action: onUndo) {
                    Text("Undo")
                        .font(AppFont.ui(13.5, .bold))
                        .foregroundStyle(Palette.indigoLight)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Palette.coachInk))
        .shadow(color: Color(hex: 0x141620).opacity(0.3), radius: 14, y: 10)
    }
}

