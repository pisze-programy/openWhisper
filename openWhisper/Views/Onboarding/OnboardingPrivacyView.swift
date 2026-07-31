import SwiftUI

struct OnboardingPrivacyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.top, 24)

            Text("Your privacy")
                .font(.largeTitle.bold())

            Text("We never use your transcriptions to train models — everything stays on your device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ScreenshotPlaceholder()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct ScreenshotPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Screenshot coming soon")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
    }
}
