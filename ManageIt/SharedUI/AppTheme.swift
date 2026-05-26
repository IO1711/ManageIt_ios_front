import SwiftUI

enum AppTheme {
    // Surfaces
    static let canvas = Color(hex: 0xEDF0F6)
    static let paper = Color.white
    static let cardBorder = Color(hex: 0xE4E7F1)

    // Text
    static let ink = Color(hex: 0x1A1F36)
    static let mutedInk = Color(hex: 0x8181A5)
    static let subtleInk = Color(hex: 0xA7A7A7)
    static let outline = Color(hex: 0xE4E7F1)

    // Primary action
    static let primary = Color(hex: 0x0F2EAA)
    static let primaryHover = Color(hex: 0x5A6FC1)
    static let primarySoft = Color(hex: 0xEFF2FE)
    static let primaryOnSoft = Color(hex: 0x0F2EAA)

    // Disabled
    static let disabledBg = Color(hex: 0xF5F5F7)
    static let disabledText = Color(hex: 0xA7A7A7)

    // Role / status tag colors
    static let adminText = Color(hex: 0x8257D3)
    static let adminBg = Color(hex: 0xE6DBF8)
    static let editorText = Color(hex: 0x0F2EAA)
    static let editorBg = Color(hex: 0xA9BAFF)
    static let approvedText = Color(hex: 0x558566)
    static let approvedBg = Color(hex: 0xDFF9DD)
    static let rejectedText = Color(hex: 0xF06F66)
    static let rejectedBg = Color(hex: 0xFDE3E3)
    static let plannedText = Color(hex: 0xFF9900)
    static let plannedBg = Color(hex: 0xFFEFD8)
    static let expiredText = Color(hex: 0x8181A5)
    static let expiredBg = Color(hex: 0xEDF0F6)

    // Pairing screen accents (kept for QR scanner backdrop)
    static let scannerFrame = Color.white.opacity(0.7)
    static let alertBackground = Color(hex: 0xFDE3E3)
    static let alertBorder = Color(hex: 0xF06F66)
    static let badgeBackground = Color(hex: 0xEFF2FE)

    // Legacy alias still referenced by pairing buttons - mapped to primary
    static let deepClay = Color(hex: 0x0F2EAA)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Card / Panel

private struct MuseumPanelModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppTheme.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppTheme.ink.opacity(0.05), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func museumPanel(padding: CGFloat = 20) -> some View {
        modifier(MuseumPanelModifier(padding: padding))
    }
}

// MARK: - Primary button

struct PrimaryButtonStyle: ButtonStyle {
    var fillWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.primaryHover : AppTheme.primary)
            )
            .opacity(configuration.isPressed ? 0.95 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.primarySoft.opacity(0.7) : AppTheme.primarySoft)
            )
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.rejectedText)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.rejectedBg.opacity(0.7) : AppTheme.rejectedBg)
            )
    }
}

// MARK: - Tag pill

struct StatusTag: View {
    enum Kind {
        case admin, editor, approved, rejected, planned, expired, neutral

        var foreground: Color {
            switch self {
            case .admin: return AppTheme.adminText
            case .editor: return AppTheme.editorText
            case .approved: return AppTheme.approvedText
            case .rejected: return AppTheme.rejectedText
            case .planned: return AppTheme.plannedText
            case .expired: return AppTheme.expiredText
            case .neutral: return AppTheme.mutedInk
            }
        }

        var background: Color {
            switch self {
            case .admin: return AppTheme.adminBg
            case .editor: return AppTheme.editorBg.opacity(0.55)
            case .approved: return AppTheme.approvedBg
            case .rejected: return AppTheme.rejectedBg
            case .planned: return AppTheme.plannedBg
            case .expired: return AppTheme.expiredBg
            case .neutral: return AppTheme.disabledBg
            }
        }
    }

    let text: String
    let kind: Kind

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(kind.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous).fill(kind.background)
            )
    }
}

// MARK: - Field label

struct FieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.mutedInk)
    }
}

// MARK: - Form field container

struct FormFieldContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(title: title)
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                )
        }
    }
}
