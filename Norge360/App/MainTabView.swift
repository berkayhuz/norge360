import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @EnvironmentObject private var groupChatStore: CommunityGroupChatStore
    @StateObject private var profileTabAvatar = ProfileTabAvatarLoader()

    var body: some View {
        TabView(selection: tabSelection) {
            CommunityFeedView()
                .tag(AppTabRouter.Tab.home)
            ExploreView()
                .tag(AppTabRouter.Tab.explore)
            CommunityConversationsView()
                .tag(AppTabRouter.Tab.messages)
            CommunityHubView()
                .tag(AppTabRouter.Tab.community)
            NavigationStack(path: $tabRouter.profilePath) {
                ProfileView()
                    .navigationDestination(for: UUID.self) { userID in
                        CommunityMemberProfileView(userID: userID)
                    }
            }
            .tag(AppTabRouter.Tab.profile)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomTabBar(
                selection: tabSelection,
                profileImage: profileTabAvatar.image,
                labels: AppTabRouter.Tab.allCases.map { tab in
                    AppStrings.localized("tabs.\(tab.localizationKey)")
                }
            )
            .frame(height: 49)
        }
        .tint(.norgePrimary)
        .task(id: communityProfileStore.profile?.avatarURL) {
            profileTabAvatar.load(from: communityProfileStore.profile?.avatarURL)
        }
        .task(id: tabRouter.selectedTab.rawValue) {
            guard tabRouter.selectedTab == .messages else { return }
            groupChatStore.activate()
        }
    }

    private var tabSelection: Binding<AppTabRouter.Tab> {
        Binding(
            get: { tabRouter.selectedTab },
            set: { tabRouter.selectTab($0) }
        )
    }
}

private struct NativeBottomTabBar: UIViewRepresentable {
    @Binding var selection: AppTabRouter.Tab
    let profileImage: UIImage?
    let labels: [String]

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> UITabBar {
        let tabBar = UITabBar()
        tabBar.delegate = context.coordinator
        tabBar.isTranslucent = false
        tabBar.itemPositioning = .fill
        configure(tabBar)
        return tabBar
    }

    func updateUIView(_ tabBar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        configure(tabBar)
    }

    private func configure(_ tabBar: UITabBar) {
        let symbols = ["house", "magnifyingglass", "paperplane", "person.3", "person.crop.circle"]
        let items = AppTabRouter.Tab.allCases.enumerated().map { index, tab in
            let image: UIImage?
            if tab == .profile, let profileImage {
                image = profileImage.withRenderingMode(.alwaysOriginal)
            } else {
                image = UIImage(systemName: symbols[index])
            }

            let item = UITabBarItem(title: nil, image: image, selectedImage: image)
            item.accessibilityLabel = labels.indices.contains(index) ? labels[index] : nil
            item.accessibilityTraits = .button
            return item
        }
        tabBar.items = items
        tabBar.selectedItem = items.indices.contains(selection.rawValue) ? items[selection.rawValue] : nil

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        let primaryColor = UIColor(red: 71 / 255, green: 145 / 255, blue: 231 / 255, alpha: 1)
        appearance.stackedLayoutAppearance.selected.iconColor = primaryColor
        appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        appearance.backgroundColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1)
            } else {
                UIColor(red: 248 / 255, green: 248 / 255, blue: 248 / 255, alpha: 1)
            }
        }
        tabBar.tintColor = primaryColor
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<AppTabRouter.Tab>

        init(selection: Binding<AppTabRouter.Tab>) {
            self.selection = selection
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(of: item),
                let tab = AppTabRouter.Tab(rawValue: index)
            else { return }
            selection.wrappedValue = tab
        }
    }
}
