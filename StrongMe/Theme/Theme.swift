//
//  Theme.swift
//  StrongMe
//
//  Design system ported from Ref/today-screen-prototype.html.
//  Calm, voice-first: oat canvas, indigo accent, apricot reserved for protein.
//

import SwiftUI

// MARK: - Palette

enum Palette {
    /// App canvas: soft oat, calm, not cream
    static let app = Color(hex: 0xEEEDE8)
    /// Card surfaces
    static let surface = Color(hex: 0xFBFBF9)
    /// Deep indigo-ink primary text
    static let ink = Color(hex: 0x1E2230)
    /// Secondary text
    static let muted = Color(hex: 0x7C808E)
    /// Hairlines
    static let hairline = Color(hex: 0xE4E3DC)
    /// Primary accent
    static let indigo = Color(hex: 0x4C5A96)
    /// Accent light (gradient end)
    static let indigoLight = Color(hex: 0x828FCB)
    /// The one warm signal — protein only
    static let apricot = Color(hex: 0xE39A63)
    static let apricotSoft = Color(hex: 0xF3D9C4)
    /// Serif body ink used in coach-voice text
    static let coachInk = Color(hex: 0x242A3D)

    /// Insight / soft indigo card gradient
    static let insightGradient = LinearGradient(
        colors: [Color(hex: 0xF4F5FA), Color(hex: 0xEDEFF7)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let insightBorder = Color(hex: 0xE4E7F1)

    /// The talk control gradient
    static let talkGradient = LinearGradient(
        colors: [indigo, Color(hex: 0x5D6BAB), indigoLight],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let confirmGradient = LinearGradient(
        colors: [indigo, indigoLight],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let proteinGradient = LinearGradient(
        colors: [Color(hex: 0xE7A876), apricot],
        startPoint: .leading, endPoint: .trailing
    )
    /// Care / distress card
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
        return .custom(name, size: size)
    }

    /// Inter — labels, values, buttons, everything else.
    static func ui(_ size: CGFloat, _ weight: UIWeight = .regular) -> Font {
        let name = switch weight {
        case .regular: "Inter-Regular"
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold: "Inter-Bold"
        }
        return .custom(name, size: size)
    }
}

// MARK: - Shared card chrome

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
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
