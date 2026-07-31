import SwiftUI

struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        ZStack {
            if let message = toast.message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.8)))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 140)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toast.message)
    }
}
