import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 0.94, green: 0.92, blue: 0.88)
    static let paper = Color(red: 0.985, green: 0.972, blue: 0.94)
    static let ink = Color(red: 0.18, green: 0.16, blue: 0.15)
    static let mutedInk = Color(red: 0.37, green: 0.34, blue: 0.31)
    static let subtleInk = Color(red: 0.47, green: 0.43, blue: 0.39)
    static let outline = Color(red: 0.78, green: 0.72, blue: 0.64)
    static let badgeBackground = Color(red: 0.9, green: 0.84, blue: 0.77)
    static let deepClay = Color(red: 0.57, green: 0.34, blue: 0.25)
    static let scannerFrame = Color.white.opacity(0.7)
    static let alertBackground = Color(red: 0.98, green: 0.92, blue: 0.86)
    static let alertBorder = Color(red: 0.83, green: 0.67, blue: 0.55)
}

private struct MuseumPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AppTheme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(AppTheme.outline.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func museumPanel() -> some View {
        modifier(MuseumPanelModifier())
    }
}
