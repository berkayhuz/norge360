import SwiftUI

/// The Community tab begins with events: the most immediate way to meet people
/// locally. Groups and the relocation plan stay one tap away in the same context.
struct CommunityHubView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter
    @State private var section: CommunitySection = .events
    @State private var isPresentingCreateEvent = false
    @State private var isPresentingCreateGroup = false
    @State private var isShowingLikedEvents = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CommunitySectionHeader(
                    section: $section,
                    isPresentingCreateEvent: $isPresentingCreateEvent,
                    isPresentingCreateGroup: $isPresentingCreateGroup,
                    isShowingLikedEvents: $isShowingLikedEvents
                )
                .padding(.horizontal, NorgeSpacing.medium)
                .frame(maxWidth: .infinity)
                .background(Color.norgeTopBarBackground)

                ZStack {
                    // Keep Events mounted while Groups/Plan is shown. Returning
                    // to it therefore updates only its list state instead of
                    // reconstructing the parent screen and section header.
                    CommunityEventsView(
                        usesEmbeddedChrome: true,
                        tracksTabBarScroll: section == .events
                    )
                    .opacity(section == .events ? 1 : 0)
                    .allowsHitTesting(section == .events)
                    .accessibilityHidden(section != .events)

                    if section == .groups {
                        CommunityGroupsView(
                            usesEmbeddedChrome: true,
                            tracksTabBarScroll: section == .groups
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationDestination(isPresented: $isShowingLikedEvents) {
                CommunityEventsView(showsLikedOnly: true)
            }
            .onChange(of: isShowingLikedEvents) { _, isPresented in
                tabRouter.isCommunityLikedEventsFlowActive = isPresented
                tabRouter.isTabBarHidden = isPresented
            }
            .scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .presentationBackground(Color.norgeAppBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingCreateEvent) {
                CreateCommunityEventView()
            }
            .sheet(isPresented: $isPresentingCreateGroup) {
                CreateCommunityGroupView()
            }
        }
    }
}

private enum CommunitySection: String, CaseIterable, Identifiable {
    case events, groups
    var id: String { rawValue }
    var title: String { AppStrings.localized("community.section.\(rawValue)") }
}

private struct CommunitySectionHeader: View {
    @Binding var section: CommunitySection
    @Binding var isPresentingCreateEvent: Bool
    @Binding var isPresentingCreateGroup: Bool
    @Binding var isShowingLikedEvents: Bool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(CommunitySection.allCases) { item in
                Button {
                    section = item
                } label: {
                    Text(item.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(section == item ? Color.primary : Color.secondary.opacity(0.58))
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if section == .events {
                Button {
                    isPresentingCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(AppStrings.localized("events.create"))
                Button {
                    isShowingLikedEvents = true
                } label: {
                    Image(systemName: "heart")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(AppStrings.localized("events.liked_title"))
            } else {
                Button {
                    isPresentingCreateGroup = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(AppStrings.localized("groups.create"))
            }
        }
    }
}
