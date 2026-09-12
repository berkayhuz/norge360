import SwiftUI

/// Shared dimensions for every first-level navigation surface.
enum NorgeTopBarMetrics {
    static let height: CGFloat = 56
    static let horizontalPadding: CGFloat = NorgeSpacing.small
    static let itemSpacing: CGFloat = NorgeSpacing.extraSmall
    static let actionSize: CGFloat = NorgeControlSize.tapTarget
    static let symbolSize: CGFloat = 21
    static let searchHeight: CGFloat = NorgeControlSize.tapTarget
    static let searchCornerRadius: CGFloat = NorgeCornerRadius.smallCard
}

/// The common container used by custom root-screen headers.
struct NorgeTopBar<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal, NorgeTopBarMetrics.horizontalPadding)
            .frame(minHeight: NorgeTopBarMetrics.height)
            .background(Color.norgeTopBarBackground)
            .accessibilityElement(children: .contain)
    }
}

/// A single icon treatment for custom headers and native toolbar items.
struct NorgeTopBarActionLabel: View {
    let systemName: String
    var badgeText: String?
    var symbolSize: CGFloat = NorgeTopBarMetrics.symbolSize

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .frame(width: NorgeTopBarMetrics.actionSize, height: NorgeTopBarMetrics.actionSize)

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
                    .offset(x: 5, y: -2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: NorgeTopBarMetrics.actionSize, height: NorgeTopBarMetrics.actionSize)
        .contentShape(Rectangle())
    }
}

/// Shared title styling for principal toolbar content and custom headers.
struct NorgeTopBarTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minHeight: NorgeTopBarMetrics.actionSize)
    }
}

/// The canonical search field used in Explore, Messages and contextual search bars.
struct NorgeTopBarSearchField: View {
    @Binding var text: String
    let prompt: String
    let showsClearButton: Bool
    private let focus: FocusState<Bool>.Binding?
    private let accessory: AnyView?

    init(
        text: Binding<String>,
        prompt: String,
        focus: FocusState<Bool>.Binding? = nil,
        showsClearButton: Bool = true
    ) {
        _text = text
        self.prompt = prompt
        self.focus = focus
        self.showsClearButton = showsClearButton
        accessory = nil
    }

    init<Accessory: View>(
        text: Binding<String>,
        prompt: String,
        focus: FocusState<Bool>.Binding? = nil,
        showsClearButton: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        _text = text
        self.prompt = prompt
        self.focus = focus
        self.showsClearButton = showsClearButton
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(spacing: NorgeTopBarMetrics.itemSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            searchTextField

            if showsClearButton && !text.isEmpty {
                Button {
                    text = ""
                    focus?.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: NorgeTopBarMetrics.searchHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("search.clear"))
            }

            if let accessory { accessory }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, minHeight: NorgeTopBarMetrics.searchHeight)
        .background(
            Color.norgeInputSurface,
            in: RoundedRectangle(cornerRadius: NorgeTopBarMetrics.searchCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var searchTextField: some View {
        let field = TextField(prompt, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityLabel(prompt)

        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}
