import Foundation

enum CommunityProfileLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

@MainActor
final class CommunityProfileStore: ObservableObject {
    @Published private(set) var profile: CommunityProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var loadState: CommunityProfileLoadState = .idle

    private let service: any CommunityProfileProviding
    private var activeUserID: UUID?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(service: any CommunityProfileProviding) {
        self.service = service
    }

    var requiresSetup: Bool { loadState == .loaded && profile == nil }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        activeUserID = user?.id
        profile = nil
        loadState = user == nil ? .idle : .loading

        guard user != nil else {
            isLoading = false
            return
        }

        isLoading = true
        startProfileLoad()
    }

    /// Profile media uses short-lived signed URLs. Refresh the owner profile
    /// directly rather than reusing the general feed's profile cache.
    func refreshProfile() async {
        guard activeUserID != nil else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        isLoading = profile == nil
        startProfileLoad()
        await loadTask?.value
    }

    func completeProfile(_ input: CommunityProfileSetupInput) async throws {
        let normalizedCity = input.cityOrRegion?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedUsername = CommunityUsernameRules.normalized(input.username) else {
            throw CommunityProfileError.invalidUsername
        }
        profile = try await service.saveProfile(
            CommunityProfileDraft(
                displayName: input.displayName,
                username: normalizedUsername,
                preferredLocale: input.preferredLanguage.rawValue,
                norwayStatus: input.norwayStatus,
                cityOrRegion: normalizedCity?.isEmpty == true ? nil : normalizedCity,
                publicLanguages: [input.preferredLanguage.rawValue],
                interests: input.interests.map(\.rawValue).sorted(),
                isPublic: true
            )
        )
        loadState = .loaded
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
        try await service.isUsernameAvailable(username)
    }

    func updateAvatar(with image: CommunityImageUpload) async throws {
        profile = try await service.updateAvatar(with: image)
        loadState = .loaded
    }

    func updateCover(with image: CommunityImageUpload) async throws {
        profile = try await service.updateCover(with: image)
        loadState = .loaded
    }

    func updateVisibility(isPublic: Bool) async throws {
        profile = try await service.updateVisibility(isPublic: isPublic)
        loadState = .loaded
    }

    func updateFieldVisibility(showNorwayStatus: Bool, showLocation: Bool) async throws {
        profile = try await service.updateFieldVisibility(
            showNorwayStatus: showNorwayStatus,
            showLocation: showLocation
        )
        loadState = .loaded
    }

    func updatePreferredLanguage(_ language: AppLanguage) async throws {
        profile = try await service.updatePreferredLanguage(language)
        loadState = .loaded
    }

    func updateDetails(_ input: CommunityProfileDetailsInput) async throws {
        guard let normalizedDisplayName = CommunityContentRules.normalizedDisplayName(input.displayName),
            let normalizedUsername = CommunityUsernameRules.normalized(input.username),
            input.biography.isEmpty || CommunityContentRules.normalizedBiography(input.biography) != nil,
            let profile
        else {
            throw CommunityProfileError.invalidProfileDetails
        }

        let normalizedCity = input.cityOrRegion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profile = try await service.updateDetails(
            CommunityProfileDraft(
                displayName: normalizedDisplayName,
                username: normalizedUsername,
                preferredLocale: profile.preferredLocale,
                norwayStatus: input.norwayStatus,
                cityOrRegion: normalizedCity?.isEmpty == true ? nil : normalizedCity,
                publicLanguages: profile.publicLanguages,
                interests: input.interests.map(\.rawValue).sorted(),
                isPublic: profile.isPublic,
                biography: CommunityContentRules.normalizedBiography(input.biography)
            ))
        loadState = .loaded
    }

    private func startProfileLoad() {
        guard let userID = activeUserID, loadTask == nil else { return }
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedProfile = try await service.loadProfile()
                guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
                profile = loadedProfile
                loadState = .loaded
            } catch {
                // Keep the last known profile and its media paths available while
                // offline. The image cache can continue rendering the last image.
                guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
                loadState = .failed
            }
            guard activeUserID == userID, loadGeneration == generation else { return }
            isLoading = false
            loadTask = nil
        }
    }
}

enum CommunityProfileError: LocalizedError {
    case invalidUsername
    case invalidProfileDetails

    var errorDescription: String? {
        switch self {
        case .invalidUsername:
            AppStrings.localized("account_setup.username_unavailable")
        case .invalidProfileDetails:
            AppStrings.localized("profile.details_error")
        }
    }
}
