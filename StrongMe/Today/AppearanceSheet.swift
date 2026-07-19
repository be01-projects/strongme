//
//  AppearanceSheet.swift
//  StrongMe
//
//  The A/B switch while we live with both looks. Temporary surface —
//  once a style wins, this sheet and its header button go away.
//

import SwiftUI

struct AppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UIStyle.storageKey) private var styleRaw = UIStyle.card.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)

            HStack(spacing: 8) {
                IndigoDot()
                EyebrowLabel(text: "Appearance", color: Palette.indigo)
            }

            Text("Two looks, same app. Live with each for a bit — we'll keep the one that feels right.")
                .font(AppFont.coach(16))
                .foregroundStyle(Color(hex: 0x565B6B))
                .lineSpacing(4)
                .padding(.top, 12)
                .padding(.bottom, 18)

            optionRow(
                style: .card,
                title: "Soft cards",
                blurb: "The original — surfaces, gentle shadows, everything in its own container."
            )
            .padding(.bottom, 10)

            optionRow(
                style: .journal,
                title: "Journal",
                blurb: "Borderless and typographic — serif numerals, thin rules, more paper than dashboard."
            )
            .padding(.bottom, 10)

            optionRow(
                style: .daybook,
                title: "Daybook",
                blurb: "A different take: your day as a visible thread, stats as one quiet strip, warm clay instead of indigo."
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
    }

    private func optionRow(style: UIStyle, title: String, blurb: String) -> some View {
        let selected = styleRaw == style.rawValue
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                styleRaw = style.rawValue
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                stylePreview(style)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.coach(17, .medium))
                        .foregroundStyle(Palette.ink)
                    Text(blurb)
                        .font(AppFont.ui(12.5, .medium))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Palette.indigo : Palette.hairline)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Palette.indigo : Palette.hairline,
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// A tiny abstract render of each style
    @ViewBuilder
    private func stylePreview(_ style: UIStyle) -> some View {
        VStack(spacing: 4) {
            switch style {
            case .card:
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xEDEFF7)).frame(height: 14)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.hairline))
                    RoundedRectangle(cornerRadius: 3).fill(.white).frame(height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.hairline))
                }
                Capsule().fill(Palette.apricot.opacity(0.7)).frame(height: 4)
            case .journal:
                Text("Aa")
                    .font(AppFont.coach(13, .medium))
                    .foregroundStyle(Color(hex: 0x1E2230))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color(hex: 0xE4E3DC)).frame(height: 1)
                Rectangle().fill(Color(hex: 0xE4E3DC)).frame(height: 1)
                Rectangle().fill(Color(hex: 0xE39A63)).frame(height: 2)
            case .daybook:
                Rectangle().fill(Color(hex: 0xC4693B)).frame(height: 3)
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0xE6DED2)).frame(height: 6)
                    }
                }
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xFCF9F3)).frame(height: 9)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0xE6DED2)))
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xFCF9F3)).frame(height: 9)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0xE6DED2)))
            }
        }
        .frame(width: 52)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: style == .daybook ? 0xF4EEE6 : 0xEEEDE8))
        )
    }
}
