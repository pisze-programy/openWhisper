import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    var onSkip: (() -> Void)? = nil

    private enum Step: Int, CaseIterable {
        case intro, model, privacy

        @ViewBuilder
        var content: some View {
            switch self {
            case .intro: OnboardingIntroView()
            case .model: OnboardingModelView()
            case .privacy: OnboardingPrivacyView()
            }
        }
    }

    @State private var step = Step.intro

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    ForEach(Step.allCases, id: \.self) { page in
                        ScrollView {
                            page.content
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.hidden)
                        .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))

                primaryButton
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { skip() }
                }
            }
        }
    }

    private var primaryButton: some View {
        Button {
            if let next = nextStep {
                withAnimation { step = next }
            } else {
                onFinish()
            }
        } label: {
            Text(nextStep == nil ? "Finish" : "Continue")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var nextStep: Step? {
        guard let index = Step.allCases.firstIndex(of: step),
              index < Step.allCases.count - 1 else {
            return nil
        }
        return Step.allCases[index + 1]
    }

    private func skip() {
        if let onSkip {
            onSkip()
        } else {
            onFinish()
        }
    }
}
