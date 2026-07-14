//
//  CoachSheet.swift
//  StrongMe
//
//  "How am I doing?" review on open, suggestion chips, free-form ask.
//  The privacy tradeoff is handled in the open: "What your coach can see"
//  shows the exact summary that was sent, verbatim.
//

import SwiftData
import SwiftUI

struct CoachSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health

    @AppStorage("proteinTargetGrams") private var proteinTarget = 150.0

    @State private var session = CoachSession()
    @State private var question = ""
    @State private var showDataDisclosure = false
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "What should I eat tonight?",
        "Should I train today?",
        "Am I on track?",
        "How's my mood been?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        reviewSection
                        if session.isLive && session.review != nil && session.bubbles.isEmpty {
                            suggestionChips
                                .padding(.top, 18)
                        }
                        conversation
                        if session.isThinking && session.review != nil {
                            thinkingIndicator
                                .padding(.top, 14)
                        }
                        dataDisclosure
                            .padding(.top, 22)
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: session.bubbles) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            footer
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.app)
        .presentationCornerRadius(30)
        .task {
            await session.start(context: modelContext, health: health, proteinTarget: proteinTarget)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0xD6D5CD))
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)
            HStack(spacing: 8) {
                IndigoDot()
                EyebrowLabel(text: "Your coach", color: Palette.indigo)
                Spacer()
            }
            .padding(.horizontal, 22)
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if let review = session.review {
            Text(markdown(review))
                .font(AppFont.coach(19))
                .foregroundStyle(Color(hex: 0x2A2F42))
                .lineSpacing(6)
                .padding(.top, 10)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                thinkingIndicator
                Text("Reading your week…")
                    .font(AppFont.coach(17))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 16)
        }
    }

    private var suggestionChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    Task { await session.ask(suggestion) }
                } label: {
                    Text(suggestion)
                        .font(AppFont.ui(13, .medium))
                        .foregroundStyle(Palette.indigo)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0xF4F5FA)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0xDADCE8)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 14) {
            ForEach(session.bubbles) { bubble in
                switch bubble.role {
                case .user:
                    Text(bubble.text)
                        .font(AppFont.ui(14, .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 17, bottomLeadingRadius: 17,
                                bottomTrailingRadius: 4, topTrailingRadius: 17,
                                style: .continuous
                            )
                            .fill(LinearGradient(colors: [Palette.indigo, Color(hex: 0x6673B3)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.leading, 60)
                case .coach:
                    Text(markdown(bubble.text))
                        .font(AppFont.ui(14.5))
                        .foregroundStyle(Color(hex: 0x2A2F42))
                        .lineSpacing(4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 17, bottomLeadingRadius: 4,
                                bottomTrailingRadius: 17, topTrailingRadius: 17,
                                style: .continuous
                            )
                            .fill(Palette.surface)
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 17, bottomLeadingRadius: 4,
                                bottomTrailingRadius: 17, topTrailingRadius: 17,
                                style: .continuous
                            )
                            .strokeBorder(Palette.hairline)
                        )
                        .cardShadow()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 36)
                }
            }
        }
        .padding(.top, session.bubbles.isEmpty ? 0 : 20)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking it through…")
                .font(AppFont.ui(12.5, .medium))
                .foregroundStyle(Palette.muted)
        }
    }

    private var dataDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { showDataDisclosure.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 11, weight: .medium))
                    Text("What your coach can see")
                        .font(AppFont.ui(12, .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showDataDisclosure ? 180 : 0))
                }
                .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)

            if showDataDisclosure {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This summary — and only this — leaves your phone when you talk to the coach. Everything else stays on device.")
                        .font(AppFont.ui(11.5, .medium))
                        .foregroundStyle(Palette.muted)
                    Text(session.dataSummary.isEmpty ? "…" : session.dataSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x3A3F52))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Your coach — not a doctor or dietitian. It defers on anything medical.")
                .font(AppFont.ui(10.5, .medium))
                .kerning(0.1)
                .foregroundStyle(Color(hex: 0xA4A6AF))

            HStack(spacing: 10) {
                TextField("Ask anything about your data…", text: $question)
                    .font(AppFont.ui(15))
                    .focused($inputFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(inputFocused ? Palette.indigo : Palette.hairline)
                    )
                    .submitLabel(.send)
                    .onSubmit(send)
                    .disabled(!session.isLive)

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.confirmGradient))
                }
                .buttonStyle(.plain)
                .disabled(!session.isLive || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Palette.app)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    private func send() {
        let text = question
        question = ""
        Task { await session.ask(text) }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
