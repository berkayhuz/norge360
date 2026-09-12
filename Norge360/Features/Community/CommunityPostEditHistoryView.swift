import SwiftUI

/// Read-only audit presentation for a post's prior revisions.
struct CommunityPostEditHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedStore: CommunityFeedStore

    let postID: UUID
    @State private var history: [CommunityPostEditHistory] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    NorgeLoadingState()
                } else if history.isEmpty {
                    NorgeUnavailableState(
                        AppStrings.localized("post.edit_history_empty_title"),
                        systemImage: "clock.arrow.circlepath",
                        description: AppStrings.localized("post.edit_history_empty_body")
                    )
                } else {
                    List(history) { revision in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(revision.previousBody)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(Self.relativeDateFormatter.localizedString(for: revision.editedAt, relativeTo: .now))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, NorgeSpacing.xxs)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .navigationTitle(AppStrings.localized("post.edit_history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("feed.cancel")) { dismiss() }
                }
                .norgePlainToolbar()
            }
            .task { await loadHistory() }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    NorgeInlineFeedback(message: errorMessage)
                        .padding()
                }
            }
        }
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            history = try await feedStore.postEditHistory(for: postID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
