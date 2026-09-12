import SwiftUI

extension UIColor {
    static let norgeAppBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 37.0 / 255.0, alpha: 1) : .systemBackground
    }
    static let norgeTopBarBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 30.0 / 255.0, alpha: 1) : .systemBackground
    }
}

extension Color {
    static let norgePrimary = Color(red: 71.0 / 255.0, green: 145.0 / 255.0, blue: 231.0 / 255.0)
    static let norgeTextOnLight = Color.primary
    static let norgeMutedTextOnLight = Color.secondary
    static let norgeAppBackground = Color(uiColor: .norgeAppBackground)
    static let norgeTopBarBackground = Color(uiColor: .norgeTopBarBackground)
    static let norgeInputSurface = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 55.0 / 255.0, alpha: 1) : .secondarySystemBackground
        })
    static let norgePhotoScrim = Color(red: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255)
}

@MainActor
enum NorgeAppearance {
    static func configure() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = .norgeTopBarBackground
        navigation.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UITableView.appearance().backgroundColor = .norgeAppBackground
        UITableViewCell.appearance().backgroundColor = .norgeAppBackground
        UICollectionView.appearance().backgroundColor = .norgeAppBackground
        UIWindow.appearance().backgroundColor = .norgeAppBackground
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = .norgeAppBackground
        tabs.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func norgePlainToolbar() -> some ToolbarContent {
        if #available(iOS 26.0, *) { self.sharedBackgroundVisibility(.hidden) } else { self }
    }
}

extension View {
    func norgeScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Color.norgeAppBackground)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(Color.norgeTopBarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .presentationBackground(Color.norgeAppBackground)
    }
}
