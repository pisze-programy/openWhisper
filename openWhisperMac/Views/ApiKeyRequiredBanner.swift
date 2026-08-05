import SwiftUI
import OpenWhisperShared

/// Banner shown at the top of the Formatting and Translate tabs when the
/// OpenRouter API key is missing. Explains why the options below are disabled
/// and where to add the key. Hides itself once a key is stored.
struct ApiKeyRequiredBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("API key required")
                    .font(.callout.weight(.medium))
                Text("Translation and AI formatting need an OpenRouter API key. Add it in Settings → API Key to enable these options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.25), lineWidth: 1)
        )
    }
}
