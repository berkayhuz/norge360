import SwiftUI

/// Shared layout and surface for direct and group chat bubbles.
struct CommunityChatBubbleContainer<Content: View, Menu: View>: View {
    let isMine: Bool
    let outgoingColor: Color
    var cornerRadius: CGFloat = 18
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 10
    @ViewBuilder let content: Content
    @ViewBuilder let menu: Menu

    init(
        isMine: Bool,
        outgoingColor: Color,
        cornerRadius: CGFloat = 18,
        horizontalPadding: CGFloat = 14,
        verticalPadding: CGFloat = 10,
        @ViewBuilder content: () -> Content,
        @ViewBuilder menu: () -> Menu
    ) {
        self.isMine = isMine
        self.outgoingColor = outgoingColor
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
        self.menu = menu()
    }

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 44) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) { content }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    isMine ? outgoingColor : Color.norgeInputSurface,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .contextMenu { menu }
            if !isMine { Spacer(minLength: 44) }
        }
    }
}
