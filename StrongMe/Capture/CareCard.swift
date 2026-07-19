//
//  CareCard.swift
//  StrongMe
//
//  The distress response — warmth and a nudge toward real support, never
//  a chirpy "logged!". Shared by the capture flow and the Siri path
//  (a distress entry via Siri opens the app to this, full screen — it
//  should never be compressed into a banner).
//

import SwiftUI

struct CareCard: View {
    var body: some View {
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
    }
}

/// Standalone presentation for when a distress entry arrives via Siri and
/// the app opens to respond properly.
struct CareSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)

            CareCard()
                .padding(.bottom, 14)

            Button { dismiss() } label: {
                Text("Okay").confirmButtonStyle()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
    }
}
