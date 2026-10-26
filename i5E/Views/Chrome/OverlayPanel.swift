import ContentKit
import SwiftUI

struct OverlayPanel<Content: View>: View {
    let title: String
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    private var theme: ReadingTheme { .resolve(colorScheme) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                HStack {
                    Text(title).font(.headline).foregroundStyle(theme.text)
                    Spacer()
                    Button("完成") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                Divider()
                content
            }
            .frame(minWidth: 380, maxWidth: 560, minHeight: 320, maxHeight: 640)
            .background(theme.surface)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
            .padding(40)
        }
        .transition(.opacity)
    }
}
