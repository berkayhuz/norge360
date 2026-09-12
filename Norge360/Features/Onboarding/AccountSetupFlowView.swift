import SwiftUI
import UIKit

// Required, first-account setup. Relocation planning remains a separate flow.
struct AccountSetupFlowView: View {
    @EnvironmentObject private var accountSetupStore: AccountSetupStore
    @EnvironmentObject private var communityProfileStore: CommunityProfileStore
    @EnvironmentObject private var languageSettings: LanguageSettings
    @EnvironmentObject private var sessionCoordinator: SessionCoordinator

    @State private var step: Int
    @State private var displayName = ""
    @State private var username = ""
    @State private var usernameAvailability: UsernameAvailability = .idle
    @State private var norwayStatus: NorwayStatus = .planningMove
    @State private var cityOrRegion = ""
    @State private var selectedInterests: Set<CommunityInterest> = []
    @State private var selectedLanguage = LanguageSettings.selectedLanguage
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isRegionPickerPresented = false
    @State private var isLanguagePickerPresented = false

    // Welcome plus five profile questions. Phone verification remains deferred.
    private let stepCount = 6

    init(initialStep: Int = 0) {
        _step = State(initialValue: min(max(initialStep, 0), stepCount - 1))
    }

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    AccountSetupWelcomeView(onNext: { step = 1 }, onBack: returnToGetStarted)
                } else {
                    AccountSetupStepLayout(
                        currentStep: step,
                        totalSteps: stepCount - 1,
                        title: navigationTitle,
                        errorMessage: errorMessage,
                        primaryTitle: primaryActionTitle,
                        isPrimaryDisabled: isWorking || !canAdvance,
                        onBack: { step -= 1 },
                        onNext: advance,
                        content: { stepContent }
                    )
                    .task(id: "\(step)-\(username)") { await checkUsernameAvailability() }
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .background(Color.norgeAppBackground.ignoresSafeArea())
        .sheet(isPresented: $isRegionPickerPresented) { CountryPicker(selectedCountry: $cityOrRegion) }
        .sheet(isPresented: $isLanguagePickerPresented) {
            AccountSetupLanguagePicker(selectedLanguage: $selectedLanguage)
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 1:
            VStack(alignment: .leading, spacing: 10) {
                NorgeCapsuleTextField(
                    placeholder: AppStrings.localized("account_setup.display_name_placeholder"),
                    text: limited($displayName, to: CommunityContentRules.maximumDisplayNameLength),
                    contentType: .nickname, capitalization: .words, height: 54)
                Text(AppStrings.localized("account_setup.display_name_note"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case 2:
            VStack(alignment: .leading, spacing: 10) {
                NorgeCapsuleTextField(
                    placeholder: AppStrings.localized("account_setup.username"),
                    text: limited($username, to: CommunityUsernameRules.maximumLength), contentType: .username,
                    capitalization: .never, height: 54)
                usernameAvailabilityView
            }
        case 3:
            VStack(spacing: 12) {
                NorgeCapsulePickerRow(title: AppStrings.localized("account_setup.norway_status")) {
                    Picker(AppStrings.localized("account_setup.norway_status"), selection: $norwayStatus) {
                        ForEach(NorwayStatus.allCases) { status in Text(status.title).tag(status) }
                    }
                    .pickerStyle(.menu)
                }
                Text(AppStrings.localized("account_setup.norway_status_note"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                Button {
                    isRegionPickerPresented = true
                } label: {
                    NorgeCapsuleDisclosureRow(
                        title: AppStrings.localized("account_setup.region"),
                        value: cityOrRegion.isEmpty
                            ? AppStrings.localized("account_setup.choose_region")
                            : String(cityOrRegion.prefix(CommunityContentRules.maximumCityOrRegionLength)))
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("account_setup.region_hint"))
                Text(AppStrings.localized("account_setup.region_note"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case 4:
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    isLanguagePickerPresented = true
                } label: {
                    NorgeCapsuleDisclosureRow(
                        title: AppStrings.localized("account_setup.preferred_language"),
                        value: selectedLanguage.nativeName)
                }
                .buttonStyle(.plain)
                Text(AppStrings.localized("account_setup.language_note"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        default:
            VStack(spacing: 10) {
                Text(AppStrings.localized("account_setup.interests_intro"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(CommunityInterest.allCases) { interest in
                    Button {
                        if selectedInterests.contains(interest) {
                            selectedInterests.remove(interest)
                        } else {
                            selectedInterests.insert(interest)
                        }
                    } label: {
                        HStack(spacing: NorgeSpacing.small) {
                            Text(interest.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selectedInterests.contains(interest) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedInterests.contains(interest) ? Color.norgePrimary : .secondary)
                        }
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: NorgeControlSize.standard)
                        .background(Color.norgeInputSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Text(AppStrings.localized("account_setup.interests_note"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case 1: AppStrings.localized("account_setup.name_title")
        case 2: AppStrings.localized("account_setup.username_title")
        case 3: AppStrings.localized("account_setup.norway_title")
        case 4: AppStrings.localized("account_setup.language_title")
        default: AppStrings.localized("account_setup.interests_section")
        }
    }

    private var primaryActionTitle: String {
        step == stepCount - 1 ? AppStrings.localized("account_setup.finish") : AppStrings.onboardingNext
    }

    private var canAdvance: Bool {
        switch step {
        case 1: CommunityContentRules.normalizedDisplayName(displayName) != nil
        case 2: usernameAvailability == .available
        default: true
        }
    }

    private func advance() {
        errorMessage = nil
        guard step == stepCount - 1 else {
            step += 1
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                guard let normalizedDisplayName = CommunityContentRules.normalizedDisplayName(displayName) else {
                    return
                }
                try await accountSetupStore.completeProfile(
                    preferredLanguage: selectedLanguage)
                try await communityProfileStore.completeProfile(
                    CommunityProfileSetupInput(
                        displayName: normalizedDisplayName,
                        username: username,
                        preferredLanguage: selectedLanguage,
                        norwayStatus: norwayStatus,
                        cityOrRegion: cityOrRegion,
                        interests: selectedInterests
                    )
                )
                languageSettings.language = selectedLanguage
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func returnToGetStarted() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await sessionCoordinator.signOut() } catch { errorMessage = error.localizedDescription }
        }
    }

    private func limited(_ value: Binding<String>, to maximum: Int) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = String($0.prefix(maximum)) })
    }

    private func checkUsernameAvailability() async {
        guard step == 2 else { return }
        guard CommunityUsernameRules.normalized(username) != nil else {
            usernameAvailability = username.isEmpty ? .idle : .unavailable
            return
        }
        usernameAvailability = .checking
        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            usernameAvailability =
                try await communityProfileStore.isUsernameAvailable(username) ? .available : .unavailable
        } catch is CancellationError { return } catch { usernameAvailability = .unavailable }
    }

    @ViewBuilder private var usernameAvailabilityView: some View {
        switch usernameAvailability {
        case .idle:
            Text(AppStrings.localized("account_setup.username_note")).font(.footnote).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text(AppStrings.localized("account_setup.username_checking"))
            }.font(.footnote).foregroundStyle(.secondary)
        case .available:
            Label(AppStrings.localized("account_setup.username_available"), systemImage: "checkmark.circle.fill").font(
                .footnote
            ).foregroundStyle(.green)
        case .unavailable:
            Label(AppStrings.localized("account_setup.username_unavailable"), systemImage: "xmark.circle.fill").font(
                .footnote
            ).foregroundStyle(.red)
        }
    }
}

private struct AccountSetupStepLayout<Content: View>: View {
    let currentStep: Int
    let totalSteps: Int
    let title: String
    let errorMessage: String?
    let primaryTitle: String
    let isPrimaryDisabled: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                Capsule().fill(Color.norgeInputSurface)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.primary).frame(
                            width: max(48, proxy.size.width * CGFloat(currentStep) / CGFloat(totalSteps)))
                    }
            }
            .frame(height: 5).padding(.top, 36)

            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(.primary).padding(.top, 42)

            content.padding(.top, 30)
            Spacer(minLength: 20)

            if let errorMessage { NorgeInlineFeedback(message: errorMessage).padding(.bottom, 10) }

            VStack(spacing: NorgeSpacing.small) {
                Button(primaryTitle, action: onNext)
                    .buttonStyle(NorgePrimaryCapsuleButtonStyle(minimumHeight: NorgeControlSize.compact))
                    .disabled(isPrimaryDisabled)
                Button(AppStrings.onboardingBack, action: onBack)
                    .buttonStyle(NorgeSecondaryCapsuleButtonStyle(minimumHeight: NorgeControlSize.compact))
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, NorgeSpacing.large)
        .background {
            Color.norgeAppBackground
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissAccountSetupKeyboard() }
        }
    }
}

private struct CountryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCountry: String
    @State private var searchText = ""

    private let countries = Locale.Region.isoRegions.compactMap {
        Locale(identifier: "en_US").localizedString(forRegionCode: $0.identifier)
    }.sorted()
    private var results: [String] {
        searchText.isEmpty ? countries : countries.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { country in
                Button(country) {
                    selectedCountry = country
                    dismiss()
                }.foregroundStyle(.primary)
            }
            .searchable(text: $searchText, prompt: AppStrings.localized("account_setup.search_countries"))
            .navigationTitle(AppStrings.localized("account_setup.choose_region"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.localized("common.cancel")) { dismiss() }
                }
            }
        }
    }
}

private struct AccountSetupLanguagePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLanguage: AppLanguage
    var body: some View {
        NavigationStack {
            List(AppLanguage.allCases) { language in
                Button {
                    selectedLanguage = language
                    dismiss()
                } label: {
                    HStack {
                        Text(language.nativeName)
                        Spacer()
                        if language == selectedLanguage { Image(systemName: "checkmark") }
                    }
                }.foregroundStyle(.primary)
            }
            .navigationTitle(AppStrings.localized("account_setup.preferred_language"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private enum UsernameAvailability: Equatable { case idle, checking, available, unavailable }
extension NorwayStatus { fileprivate var title: String { AppStrings.localized("community.status.\(rawValue)") } }
extension CommunityInterest { fileprivate var title: String { AppStrings.localized("community.interest.\(rawValue)") } }

@MainActor private func dismissAccountSetupKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
