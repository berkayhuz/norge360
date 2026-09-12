import SwiftUI

struct CommunityMessageBubble: View {
    @EnvironmentObject private var authenticationStore: AuthenticationStore
    @EnvironmentObject private var conversationsStore: CommunityConversationsStore
    let message: CommunityMessage
    let isMine: Bool
    let showsReadReceipt: Bool
    let bubbleColor: String
    let report: () -> Void
    let hide: () -> Void

    var body: some View {
        CommunityChatBubbleContainer(
            isMine: isMine,
            outgoingColor: CommunityChatPalette.color(bubbleColor).opacity(0.23),
            cornerRadius: 20
        ) {
            if let attachmentID = message.attachmentID {
                CommunityChatAttachmentImage(attachmentID: attachmentID, viewerID: authenticationStore.user?.id) { id in
                    try? await conversationsStore.imageURL(attachmentID: id)
                }
            }
            if !message.body.isEmpty {
                Text(message.body)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 5) {
                Text(message.createdAt, format: .dateTime.hour().minute())
                if showsReadReceipt {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityLabel(AppStrings.localized("messages.seen"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } menu: {
            if !isMine {
                Button(AppStrings.localized("messages.report"), systemImage: "exclamationmark.bubble") { report() }
            }
            Button(AppStrings.localized("messages.delete_for_me"), systemImage: "eye.slash", role: .destructive) {
                hide()
            }
        }
    }
}
