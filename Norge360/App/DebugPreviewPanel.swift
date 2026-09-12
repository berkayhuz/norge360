#if DEBUG
    import SwiftUI

    enum DebugPreviewDestination: String, CaseIterable, Identifiable {
        case accountWelcome
        case accountName
        case accountUsername
        case accountNorway
        case accountLanguage
        case accountInterests
        case verification
        case mainTabs

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accountWelcome: "Account setup — welcome"
            case .accountName: "Account setup — display name"
            case .accountUsername: "Account setup — username"
            case .accountNorway: "Account setup — Norway details"
            case .accountLanguage: "Account setup — language"
            case .accountInterests: "Account setup — interests"
            case .verification: "Account verification"
            case .mainTabs: "Main app tabs"
            }
        }
    }

    struct DebugPreviewPanel: View {
        let open: (DebugPreviewDestination) -> Void

        var body: some View {
            NavigationStack {
                List(DebugPreviewDestination.allCases) { destination in
                    Button(destination.title) { open(destination) }
                        .foregroundStyle(.primary)
                }
                .navigationTitle(AppStrings.localized("debug.ui_preview"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    struct DebugPreviewHost: View {
        let destination: DebugPreviewDestination
        let close: () -> Void

        var body: some View {
            ZStack(alignment: .topLeading) {
                preview
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 12)
                .accessibilityLabel(AppStrings.localized("debug.close_ui_preview"))
            }
        }

        @ViewBuilder private var preview: some View {
            switch destination {
            case .accountWelcome:
                AccountSetupFlowView(initialStep: 0)
            case .accountName:
                AccountSetupFlowView(initialStep: 1)
            case .accountUsername:
                AccountSetupFlowView(initialStep: 2)
            case .accountNorway:
                AccountSetupFlowView(initialStep: 3)
            case .accountLanguage:
                AccountSetupFlowView(initialStep: 4)
            case .accountInterests:
                AccountSetupFlowView(initialStep: 5)
            case .verification:
                AccountVerificationView(email: "preview@norge360.com")
            case .mainTabs:
                MainTabView()
            }
        }
    }
#endif
