//
//  Theme.swift
//  StrongMe
//
//  Design system ported from Ref/today-screen-prototype.html.
//  Calm, voice-first: oat canvas, indigo accent, apricot reserved for protein.
//

import SwiftUI

// MARK: - Palette

/// One complete color story. `classic` is the prototype's indigo-on-oat
/// (mind / evening register); `earthen` is Daybook's clay (body / food /
/// warmth register) — linen paper, espresso ink, pine voice, terracotta
/// protein signal.
struct PaletteSet {
    let app: UInt32
    let surface: UInt32
    let ink: UInt32
    let muted: UInt32
    let hairline: UInt32
    let primary: UInt32       // buttons, coach, rings ("indigo" slot)
    let primaryLight: UInt32
    let signal: UInt32        // protein only ("apricot" slot)
    let signalSoft: UInt32
    let coachInk: UInt32
    let insightTop: UInt32
    let insightBottom: UInt32
    let insightBorder: UInt32
    let talkMid: UInt32
    let signalGradientStart: UInt32
    let track: UInt32         // empty bar / chip-remove backgrounds

    static let classic = PaletteSet(
        app: 0xEEEDE8, surface: 0xFBFBF9, ink: 0x1E2230, muted: 0x7C808E,
        hairline: 0xE4E3DC, primary: 0x4C5A96, primaryLight: 0x828FCB,
        signal: 0xE39A63, signalSoft: 0xF3D9C4, coachInk: 0x242A3D,
        insightTop: 0xF4F5FA, insightBottom: 0xEDEFF7, insightBorder: 0xE4E7F1,
        talkMid: 0x5D6BAB, signalGradientStart: 0xE7A876, track: 0xEFEDE7
    )

    static let earthen = PaletteSet(
        app: 0xF4EEE6, surface: 0xFCF9F3, ink: 0x2B241E, muted: 0x8A8075,
        hairline: 0xE6DED2, primary: 0x3F6259, primaryLight: 0x6E9188,
        signal: 0xC4693B, signalSoft: 0xEFD3C0, coachInk: 0x332B24,
        insightTop: 0xF3EBDF, insightBottom: 0xEDE2D2, insightBorder: 0xE3D6C3,
        talkMid: 0x567B71, signalGradientStart: 0xD08655, track: 0xEBE3D6
    )
}

enum Palette {
    private static var set: PaletteSet {
        UIStyle.current == .daybook ? .earthen : .classic
    }

    /// App canvas
    static var app: Color { Color(hex: set.app) }
    /// Card surfaces
    static var surface: Color { Color(hex: set.surface) }
    /// Primary text
    static var ink: Color { Color(hex: set.ink) }
    /// Secondary text
    static var muted: Color { Color(hex: set.muted) }
    /// Hairlines
    static var hairline: Color { Color(hex: set.hairline) }
    /// Primary accent (named for the classic palette; earthen maps to pine)
    static var indigo: Color { Color(hex: set.primary) }
    /// Accent light (gradient end)
    static var indigoLight: Color { Color(hex: set.primaryLight) }
    /// The one warm signal — protein only (earthen maps to terracotta)
    static var apricot: Color { Color(hex: set.signal) }
    static var apricotSoft: Color { Color(hex: set.signalSoft) }
    /// Serif body ink used in coach-voice text
    static var coachInk: Color { Color(hex: set.coachInk) }
    /// Empty tracks and small neutral fills
    static var track: Color { Color(hex: set.track) }

    /// Insight / soft tinted card gradient
    static var insightGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: set.insightTop), Color(hex: set.insightBottom)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    static var insightBorder: Color { Color(hex: set.insightBorder) }

    /// The talk control gradient
    static var talkGradient: LinearGradient {
        LinearGradient(
            colors: [indigo, Color(hex: set.talkMid), indigoLight],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
    static var confirmGradient: LinearGradient {
        LinearGradient(colors: [indigo, indigoLight],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var proteinGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: set.signalGradientStart), apricot],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Care / distress card — deliberately constant across palettes
    static let careGradient = LinearGradient(
        colors: [Color(hex: 0xF6F3FB), Color(hex: 0xEEEEF8)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let careBorder = Color(hex: 0xE6E3F1)
    static let careHeart = Color(hex: 0xC56B8A)
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

// MARK: - Typography
//
// Fraunces (serif) is the coach voice — the app speaks, it doesn't just
// display numbers. Inter carries all UI and data.

enum AppFont {
    enum SerifWeight { case regular, medium, semibold }
    enum UIWeight { case regular, medium, semibold, bold }

    /// Fraunces — greeting, daily read, coach replies, reflection text.
    static func coach(_ size: CGFloat, _ weight: SerifWeight = .regular) -> Font {
        let name = switch weight {
        case .regular: "Fraunces-Regular"
        case .medium: "Fraunces-Medium"
        case .semibold: "Fraunces-SemiBold"
        }
        return .custom(name, size: size, relativeTo: textStyle(for: size))
    }

    /// Inter — labels, values, buttons, everything else.
    static func ui(_ size: CGFloat, _ weight: UIWeight = .regular) -> Font {
        let name = switch weight {
        case .regular: "Inter-Regular"
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold: "Inter-Bold"
        }
        return .custom(name, size: size, relativeTo: textStyle(for: size))
    }

    /// Anchors each design size to the nearest system text style so the
    /// whole app scales with Dynamic Type.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<13.5: .caption
        case ..<15: .footnote
        case ..<16.5: .subheadline
        case ..<18: .callout
        case ..<20: .body
        case ..<24: .title3
        case ..<28: .title2
        default: .title
        }
    }
}

// MARK: - UI style (the A/B: soft cards vs borderless journal)

/// Two complete looks over the same layout and interactions, switchable in
/// the Appearance sheet while we live with both and pick one.
/// - `card`: the prototype's look — surfaces, hairline borders, soft shadows.
/// - `journal`: editorial — no card chrome; serif numerals, thin rules,
///   ghost outlines only where tappability needs affordance.
enum UIStyle: String {
    case card, journal, daybook

    static let storageKey = "uiStyle"

    static var current: UIStyle {
        UIStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .card
    }
}

// MARK: - Shared card chrome

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 20

    @AppStorage(UIStyle.storageKey) private var styleRaw = UIStyle.card.rawValue

    func body(content: Content) -> some View {
        switch UIStyle(rawValue: styleRaw) ?? .card {
        case .journal:
            // Ghost: presence without weight — enough affordance to touch
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Palette.surface.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        case .daybook:
            // Warm cards without the floating shadow — earthenware, not glass
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
        case .card:
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .cardShadow()
        }
    }
}

/// A thin editorial rule — the journal style's structural element
struct JournalRule: View {
    var color: Color = Palette.hairline

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 20) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }

    /// 0 1px 2px rgba(30,34,48,.05), 0 8px 24px rgba(30,34,48,.06)
    func cardShadow() -> some View {
        self
            .shadow(color: Palette.ink.opacity(0.05), radius: 1, y: 1)
            .shadow(color: Palette.ink.opacity(0.06), radius: 12, y: 8)
    }
}

/// Small uppercase section/eyebrow label
struct EyebrowLabel: View {
    let text: String
    var color: Color = Palette.muted

    var body: some View {
        Text(text.uppercased())
            .font(AppFont.ui(11.5, .semibold))
            .kerning(0.6)
            .foregroundStyle(color)
    }
}

/// The pulsing indigo dot used next to "Today's read" / "Your coach"
struct IndigoDot: View {
    var body: some View {
        Circle()
            .fill(Palette.indigo)
            .frame(width: 6, height: 6)
            .background(
                Circle()
                    .fill(Palette.indigo.opacity(0.14))
                    .frame(width: 14, height: 14)
            )
    }
}
