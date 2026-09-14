import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var tabRouter: AppTabRouter
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @EnvironmentObject private var groupChatStore: CommunityGroupChatStore
    @StateObject private var profileTabAvatar = ProfileTabAvatarLoader()
    @State private var isKeyboardVisible = false
    @State private var isNestedNavigationActive = false

    var body: some View {
        ZStack(alignment: .bottom) {
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
            .background(
                TabViewPageBounceDisabler(
                    isPagingEnabled: allowsTabPaging && !isNestedNavigationActive,
                    onNestedNavigationChanged: { isNested in
                        guard isNestedNavigationActive != isNested else { return }
                        isNestedNavigationActive = isNested
                    }
                )
            )

            if shouldShowTabBar {
                NativeBottomTabBar(
                    selectedTab: tabRouter.selectedTab,
                    onSelect: { tab in tabRouter.selectTab(tab) },
                    profileImage: profileTabAvatar.image,
                    labels: AppTabRouter.Tab.allCases.map { tab in
                        AppStrings.localized("tabs.\(tab.localizationKey)")
                    }
                )
                .frame(height: tabBarHeight)
                .scaleEffect(
                    x: tabRouter.isTabBarCompact ? 0.80 : 1,
                    y: tabRouter.isTabBarCompact ? 0.80 : 1,
                    anchor: .bottom
                )
                .padding(.bottom, 16)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .tint(.norgePrimary)
        .animation(.easeOut(duration: 0.16), value: tabRouter.isTabBarCompact)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .task(id: communityProfileStore.profile?.avatarURL) {
            profileTabAvatar.load(from: communityProfileStore.profile?.avatarURL)
        }
        .task(id: tabRouter.selectedTab.rawValue) {
            guard tabRouter.selectedTab == .messages else { return }
            groupChatStore.activate()
        }
    }

    private var shouldShowTabBar: Bool {
        guard !isKeyboardVisible, !tabRouter.isTabBarHidden, !isNestedNavigationActive else { return false }
        switch tabRouter.selectedTab {
        case .home:
            return !tabRouter.isHomeNotificationsFlowActive
        case .community:
            return !tabRouter.isCommunityLikedEventsFlowActive
        case .profile:
            return !tabRouter.isProfileSettingsFlowActive
        case .explore, .messages:
            return true
        }
    }

    private var allowsTabPaging: Bool {
        switch tabRouter.selectedTab {
        case .home:
            !tabRouter.isHomeNotificationsFlowActive
        case .community:
            !tabRouter.isCommunityLikedEventsFlowActive
        case .profile:
            !tabRouter.isProfileSettingsFlowActive
        case .explore, .messages:
            true
        }
    }

    private var tabBarHeight: CGFloat {
        50
    }

    private var tabSelection: Binding<AppTabRouter.Tab> {
        Binding(
            get: { tabRouter.selectedTab },
            set: { tabRouter.selectTab($0) }
        )
    }
}

private struct TabViewPageBounceDisabler: UIViewRepresentable {
    let isPagingEnabled: Bool
    let onNestedNavigationChanged: (Bool) -> Void

    func makeUIView(context: Context) -> BounceDisablingView {
        BounceDisablingView(isPagingEnabled: isPagingEnabled)
    }

    func updateUIView(_ uiView: BounceDisablingView, context: Context) {
        uiView.isPagingEnabled = isPagingEnabled
        uiView.onNestedNavigationChanged = onNestedNavigationChanged
        uiView.disablePagingBounce()
    }

    final class BounceDisablingView: UIView {
        var isPagingEnabled: Bool
        var onNestedNavigationChanged: (Bool) -> Void
        private var navigationProbe: Timer?

        init(
            isPagingEnabled: Bool,
            onNestedNavigationChanged: @escaping (Bool) -> Void = { _ in }
        ) {
            self.isPagingEnabled = isPagingEnabled
            self.onNestedNavigationChanged = onNestedNavigationChanged
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            navigationProbe?.invalidate()
            navigationProbe = nil
            if window != nil {
                navigationProbe = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.disablePagingBounce()
                    }
                }
            }
            disablePagingBounce()
        }

        func disablePagingBounce() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onNestedNavigationChanged(self.isNestedNavigationActive)
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView, scrollView.isPagingEnabled {
                        scrollView.bounces = false
                        scrollView.alwaysBounceHorizontal = false
                        scrollView.isScrollEnabled = isPagingEnabled
                        return
                    }
                    ancestor = view.superview
                }
                if let window {
                    disablePagingBounce(in: window)
                }
            }
        }

        private var isNestedNavigationActive: Bool {
            guard let window else { return false }

            let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            if let hitView = window.hitTest(center, with: nil) {
                var responder: UIResponder? = hitView
                while let current = responder {
                    if let viewController = current as? UIViewController,
                        let navigationController = viewController.navigationController
                    {
                        return navigationController.viewControllers.count > 1
                    }
                    responder = current.next
                }
            }

            return containsPushedNavigationController(in: window.rootViewController)
        }

        private func containsPushedNavigationController(in viewController: UIViewController?) -> Bool {
            guard let viewController else { return false }
            if let navigationController = viewController as? UINavigationController,
                navigationController.viewIfLoaded?.window != nil,
                navigationController.viewControllers.count > 1
            {
                return true
            }
            return viewController.children.reversed().contains {
                containsPushedNavigationController(in: $0)
            }
        }

        private func disablePagingBounce(in view: UIView) {
            if let scrollView = view as? UIScrollView, scrollView.isPagingEnabled {
                scrollView.bounces = false
                scrollView.alwaysBounceHorizontal = false
                scrollView.isScrollEnabled = isPagingEnabled
            }
            for subview in view.subviews {
                disablePagingBounce(in: subview)
            }
        }
    }
}

private struct NativeBottomTabBar: UIViewRepresentable {
    let selectedTab: AppTabRouter.Tab
    let onSelect: (AppTabRouter.Tab) -> Void
    let profileImage: UIImage?
    let labels: [String]

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> UITabBar {
        let tabBar = UITabBar()
        tabBar.delegate = context.coordinator
        tabBar.isTranslucent = false
        tabBar.itemPositioning = .fill
        tabBar.items = makeItems()
        configureAppearance(tabBar)
        return tabBar
    }

    func updateUIView(_ tabBar: UITabBar, context: Context) {
        context.coordinator.onSelect = onSelect
        updateItems(tabBar)
        tabBar.selectedItem =
            tabBar.items?.indices.contains(selectedTab.rawValue) == true
            ? tabBar.items?[selectedTab.rawValue]
            : nil
        configureAppearance(tabBar)
    }

    private func makeItems() -> [UITabBarItem] {
        let symbols = [
            (normal: "house", selected: "house.fill"),
            (normal: "magnifyingglass", selected: "magnifyingglass"),
            (normal: "paperplane", selected: "paperplane.fill"),
            (normal: "person.3", selected: "person.3.fill"),
            (normal: "person.crop.circle", selected: "person.crop.circle.fill"),
        ]
        return AppTabRouter.Tab.allCases.enumerated().map { index, tab in
            let item = UITabBarItem(
                title: nil,
                image: tab == .profile && profileImage != nil
                    ? profileImage : UIImage(systemName: symbols[index].normal),
                selectedImage: tab == .profile && profileImage != nil
                    ? profileImage : UIImage(systemName: symbols[index].selected)
            )
            item.accessibilityLabel = labels.indices.contains(index) ? labels[index] : nil
            item.accessibilityTraits = .button
            return item
        }
    }

    private func updateItems(_ tabBar: UITabBar) {
        guard let items = tabBar.items, items.count == AppTabRouter.Tab.allCases.count else {
            tabBar.items = makeItems()
            return
        }

        let symbols = [
            (normal: "house", selected: "house.fill"),
            (normal: "magnifyingglass", selected: "magnifyingglass"),
            (normal: "paperplane", selected: "paperplane.fill"),
            (normal: "person.3", selected: "person.3.fill"),
            (normal: "person.crop.circle", selected: "person.crop.circle.fill"),
        ]
        for (index, tab) in AppTabRouter.Tab.allCases.enumerated() {
            items[index].image =
                tab == .profile && profileImage != nil
                ? profileImage : UIImage(systemName: symbols[index].normal)
            items[index].selectedImage =
                tab == .profile && profileImage != nil
                ? profileImage : UIImage(systemName: symbols[index].selected)
            items[index].accessibilityLabel = labels.indices.contains(index) ? labels[index] : nil
        }
    }

    private func configureAppearance(_ tabBar: UITabBar) {
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
        tabBar.scrollEdgeAppearance = appearance
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var onSelect: (AppTabRouter.Tab) -> Void

        init(onSelect: @escaping (AppTabRouter.Tab) -> Void) {
            self.onSelect = onSelect
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(of: item),
                let tab = AppTabRouter.Tab(rawValue: index)
            else { return }
            onSelect(tab)
        }
    }
}
