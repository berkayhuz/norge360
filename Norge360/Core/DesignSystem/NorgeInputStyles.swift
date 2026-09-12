import SwiftUI

private struct NorgeCapsuleInputSurface: ViewModifier {
    let height: CGFloat
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Color.norgeInputSurface, in: Capsule())
    }
}

extension View {
    /// Shared capsule input surface. Validation, keyboard semantics and value
    /// bindings remain with the feature that owns the form.
    func norgeCapsuleInput(
        height: CGFloat = NorgeControlSize.compact, horizontalPadding: CGFloat = NorgeSpacing.large - 2
    )
        -> some View
    {
        modifier(NorgeCapsuleInputSurface(height: height, horizontalPadding: horizontalPadding))
    }
}

private struct NorgeOutlinedInputSurface: ViewModifier {
    let height: CGFloat
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(Color.norgeAppBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.norgePhotoScrim.opacity(0.14), lineWidth: 1))
    }
}

extension View {
    /// Shared outlined form surface used by compact authentication fields.
    func norgeOutlinedInput(
        height: CGFloat = 45, horizontalPadding: CGFloat = NorgeCornerRadius.field,
        cornerRadius: CGFloat = NorgeCornerRadius.field
    ) -> some View {
        modifier(
            NorgeOutlinedInputSurface(
                height: height,
                horizontalPadding: horizontalPadding,
                cornerRadius: cornerRadius
            ))
    }
}

private struct NorgeComposerInputSurface: ViewModifier {
    let minimumHeight: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 12)
            .frame(minHeight: minimumHeight)
            .background(Color.norgeInputSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Shared multiline composer surface for comments and conversations.
    func norgeComposerInput(
        minimumHeight: CGFloat = NorgeControlSize.compact,
        cornerRadius: CGFloat = 23,
        horizontalPadding: CGFloat = NorgeSpacing.medium - 1
    ) -> some View {
        modifier(
            NorgeComposerInputSurface(
                minimumHeight: minimumHeight,
                cornerRadius: cornerRadius,
                horizontalPadding: horizontalPadding
            ))
    }
}
