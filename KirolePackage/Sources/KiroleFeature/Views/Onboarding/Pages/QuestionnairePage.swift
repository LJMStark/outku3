import SwiftUI

public struct QuestionnairePage: View {
    let onboardingState: OnboardingState
    let questionIndex: Int

    @State private var localSelections: [String] = []

    private var question: OnboardingQuestion {
        OnboardingQuestions.allQuestions[questionIndex]
    }

    private var isLastQuestion: Bool {
        questionIndex == OnboardingQuestions.allQuestions.count - 1
    }

    public init(onboardingState: OnboardingState, questionIndex: Int) {
        self.onboardingState = onboardingState
        self.questionIndex = questionIndex
    }

    public var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: back button + progress bar
                HStack(spacing: 16) {
                    Button {
                        onboardingState.goBack()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "F3F4F6"))
                                .frame(width: 40, height: 40)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "6B7280"))
                        }
                    }

                    OnboardingProgressBar(questionIndex: questionIndex)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Question title
                        Text(question.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "1A1A2E"))
                            .padding(.top, 16)

                        if let subtitle = question.subtitle {
                            Text(subtitle)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color(hex: "6B7280"))
                                .padding(.top, 8)
                        }

                        // Options
                        VStack(spacing: 12) {
                            ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                                OptionCard(
                                    label: option.label,
                                    emoji: option.emoji,
                                    sfSymbol: option.sfSymbol,
                                    isSelected: localSelections.contains(option.id)
                                ) {
                                    handleSelect(option.id)
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: -20)),
                                    removal: .opacity
                                ))
                                .animation(.spring(response: 0.3, dampingFraction: 0.8).delay(Double(index) * 0.05), value: localSelections)
                            }
                        }
                        .padding(.top, 24)

                        // Character + dialog
                        HStack(alignment: .bottom, spacing: 12) {
                            // TODO: Replace with Kirole pet asset
                            CharacterView(imageName: "inku-main", size: 64)

                            OnboardingDialogBubble(
                                text: localSelections.isEmpty
                                    ? "Take your time, I'll wait!"
                                    : "Got it -- I'll remember that.",
                                style: .light,
                                showPointer: true
                            )
                        }
                        .padding(.top, 24)
                    }
                    .padding(.horizontal, 24)
                }

                // CTA
                OnboardingCTAButton(
                    title: "Continue",
                    isEnabled: !localSelections.isEmpty
                ) {
                    saveAnswers()
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .padding(.top, 16)
            }
        }
        .onAppear {
            localSelections = onboardingState.selectedOptions(for: question.id)
        }
    }

    private func handleSelect(_ optionId: String) {
        if question.type == .single {
            localSelections = [optionId]
        } else {
            if let index = localSelections.firstIndex(of: optionId) {
                localSelections.remove(at: index)
            } else {
                localSelections.append(optionId)
            }
        }
    }

    private func saveAnswers() {
        if question.type == .single, let selected = localSelections.first {
            onboardingState.setAnswer(questionId: question.id, value: selected)
        } else if question.type == .multiple {
            let currentSelections = onboardingState.selectedOptions(for: question.id)
            for existing in currentSelections {
                onboardingState.toggleMultiAnswer(questionId: question.id, optionId: existing)
            }
            for selected in localSelections {
                onboardingState.toggleMultiAnswer(questionId: question.id, optionId: selected)
            }
        }
    }
}
