//
//  StrongMeWidgets.swift
//  StrongMeWidgets
//
//  Glanceable protein + one-tap talk. The widget never opens the SwiftData
//  store — it renders the small snapshot the app publishes to the App Group
//  (see WidgetBridge in the app target; the snapshot struct is mirrored
//  here by hand and must stay field-compatible).
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot bridge (mirror of the app's WidgetSnapshot)

struct WidgetSnapshot: Codable {
    var dayStart: Date
    var proteinGrams: Int
    var targetGrams: Int
    var styleRaw: String
}

enum Bridge {
    static let appGroupID = "group.com.be01.StrongMe"
    static let snapshotKey = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Minimal palette (mirrors Theme.swift's classic / earthen sets)

struct MiniPalette {
    let app: Color
    let ink: Color
    let muted: Color
    let signal: Color        // protein
    let signalStart: Color   // protein gradient start
    let track: Color

    static let classic = MiniPalette(
        app: Color(hex: 0xEEEDE8), ink: Color(hex: 0x1E2230),
        muted: Color(hex: 0x7C808E), signal: Color(hex: 0xE39A63),
        signalStart: Color(hex: 0xE7A876), track: Color(hex: 0xEFEDE7)
    )
    static let earthen = MiniPalette(
        app: Color(hex: 0xF4EEE6), ink: Color(hex: 0x2B241E),
        muted: Color(hex: 0x8A8075), signal: Color(hex: 0xC4693B),
        signalStart: Color(hex: 0xD08655), track: Color(hex: 0xEBE3D6)
    )

    var proteinGradient: LinearGradient {
        LinearGradient(colors: [signalStart, signal], startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Timeline

struct ProteinEntry: TimelineEntry {
    let date: Date
    let protein: Int
    let target: Int
    let earthen: Bool

    var palette: MiniPalette { earthen ? .earthen : .classic }
    var fraction: Double { target > 0 ? min(1, Double(protein) / Double(target)) : 0 }
}

struct ProteinProvider: TimelineProvider {

    /// A stale snapshot (from yesterday) renders as 0 — the truthful read
    /// of a new day, not yesterday's number wearing today's date.
    private func entry(at date: Date) -> ProteinEntry {
        let snapshot = Bridge.load()
        let isToday = snapshot.map { Calendar.current.isDate($0.dayStart, inSameDayAs: date) } ?? false
        return ProteinEntry(
            date: date,
            protein: isToday ? (snapshot?.proteinGrams ?? 0) : 0,
            target: snapshot?.targetGrams ?? 150,
            earthen: snapshot?.styleRaw == "daybook"
        )
    }

    func placeholder(in context: Context) -> ProteinEntry {
        ProteinEntry(date: .now, protein: 84, target: 150, earthen: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProteinEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProteinEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        )
        // Two entries: now, and midnight (where the same snapshot reads 0).
        // The app pushes fresh timelines on every write in between.
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }
}

// MARK: - Protein widget (Home Screen small + Lock Screen accessories)

struct ProteinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.be01.StrongMe.Widgets.protein", provider: ProteinProvider()) { entry in
            ProteinWidgetView(entry: entry)
        }
        .configurationDisplayName("Protein today")
        .description("How today's protein is tracking against your target.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct ProteinWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProteinEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    private var small: some View {
        let p = entry.palette
        return VStack(alignment: .leading, spacing: 0) {
            Text("PROTEIN")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.4)
                .foregroundStyle(p.muted)
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.protein)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(p.ink)
                    .contentTransition(.numericText())
                Text("g")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(p.muted)
            }
            Text("of \(entry.target)g")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.muted)
            Spacer(minLength: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule()
                        .fill(p.proteinGradient)
                        .frame(width: max(8, geo.size.width * entry.fraction))
                }
            }
            .frame(height: 8)
        }
        .containerBackground(p.app, for: .widget)
        .widgetURL(URL(string: "strongme://protein"))
    }

    private var circular: some View {
        Gauge(value: entry.fraction) {
            Text("g")
        } currentValueLabel: {
            Text("\(entry.protein)")
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "strongme://protein"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Protein \(entry.protein) of \(entry.target)g")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.primary)
                        .frame(width: max(6, geo.size.width * entry.fraction))
                }
            }
            .frame(height: 6)
            Text(entry.protein >= entry.target ? "Target met" : "\(entry.target - entry.protein)g to go")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "strongme://protein"))
    }
}

// MARK: - Talk widget (Lock Screen one-tap capture)

struct TalkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.be01.StrongMe.Widgets.talk", provider: ProteinProvider()) { _ in
            TalkWidgetView()
        }
        .configurationDisplayName("Talk to StrongMe")
        .description("Straight into capture — one sentence and it's logged.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct TalkWidgetView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .medium))
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "strongme://talk"))
    }
}

// MARK: - Control Center / Action Button control

struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.be01.StrongMe.Widgets.talkControl") {
            ControlWidgetButton(action: OpenTalkIntent()) {
                Label("Talk to StrongMe", systemImage: "waveform")
            }
        }
        .displayName("Talk to StrongMe")
        .description("Open StrongMe straight into voice capture.")
    }
}

struct OpenTalkIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to StrongMe"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "strongme://talk")!))
    }
}

// MARK: - Bundle

@main
struct StrongMeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ProteinWidget()
        TalkWidget()
        TalkControl()
    }
}
