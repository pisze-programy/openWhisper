import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    var onSkip: (() -> Void)? = nil

    @State private var step = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    ScrollView {
                        OnboardingIntroView()
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .tag(0)

                    ScrollView {
                        OnboardingModelView()
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .tag(1)
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
            if step == 0 {
                withAnimation { step = 1 }
            } else {
                onFinish()
            }
        } label: {
            Text(step == 0 ? "Continue" : "Finish")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func skip() {
        if let onSkip {
            onSkip()
        } else {
            onFinish()
        }
    }
}
