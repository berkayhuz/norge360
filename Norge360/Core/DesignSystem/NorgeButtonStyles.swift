import SwiftUI

/// Shared full-width CTA styles. Keep feature flows responsible for their
/// actions and wording; this type owns only the visual/touch presentation.
struct NorgePrimaryCapsuleButtonStyle: ButtonStyle {
    var minimumHeight: CGFloat = NorgeControlSize.standard
    var font: Font = .body.weight(.semibold)
    var horizontalPadding: CGFloat = 0
    var fixedWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil, minHeight: minimumHeight)
            .frame(width: fixedWidth)
            .background(Color.norgePrimary.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

struct NorgeSecondaryCapsuleButtonStyle: ButtonStyle {
    var minimumHeight: CGFloat = NorgeControlSize.standard
    var font: Font = .body.weight(.semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .background(Color.norgeInputSurface.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
    }
}

struct NorgeCircularSendButton: View {
    let isSending: Bool
    let isEnabled: Bool
    var size: CGFloat = NorgeControlSize.compact
    var iconSize: CGFloat = 19
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up").font(.system(size: iconSize, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(isEnabled ? Color.norgePrimary : Color.norgeInputSurface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Shared social-provider button with two native surfaces used by the account
/// flows. Provider authentication stays in the owning feature.
struct NorgeSocialAuthButton: View {
    enum Surface {
        case capsule
        case roundedRectangle(cornerRadius: CGFloat)
    }

    let title: String
    let icon: String
    let iconColor: Color
    var contentColor: Color = .primary
    var backgroundColor: Color = .norgeAppBackground
    var borderColor: Color?
    var height: CGFloat = NorgeControlSize.standard
    var spacing: CGFloat = NorgeSpacing.small
    var iconFont: Font = .title2.weight(.bold)
    var titleFont: Font = .body.weight(.medium)
    var surface: Surface = .capsule
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder private var buttonContent: some View {
        switch surface {
        case .capsule:
            content
                .background(backgroundColor, in: Capsule())
                .overlay {
                    if let borderColor { Capsule().stroke(borderColor, lineWidth: 1) }
                }
        case .roundedRectangle(let cornerRadius):
            content
                .background(backgroundColor)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(borderColor ?? .clear, lineWidth: 1))
        }
    }

    private var content: some View {
        HStack(spacing: spacing) {
            Text(icon).font(iconFont).foregroundStyle(iconColor)
            Text(title).font(titleFont)
        }
        .foregroundStyle(contentColor)
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

extension NorgeSocialAuthButton {
    static func prominent(
        title: String,
        icon: String,
        iconColor: Color,
        isDark: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> NorgeSocialAuthButton {
        NorgeSocialAuthButton(
            title: title,
            icon: icon,
            iconColor: iconColor,
            contentColor: isDark ? .white : .primary,
            backgroundColor: isDark ? .black : .norgeAppBackground,
            borderColor: isDark ? nil : Color.primary.opacity(0.09),
            height: NorgeControlSize.standard,
            spacing: NorgeSpacing.medium - 2,
            iconFont: .title2.weight(.bold),
            titleFont: .body.weight(.medium),
            surface: .capsule,
            isEnabled: isEnabled,
            action: action
        )
    }
}
