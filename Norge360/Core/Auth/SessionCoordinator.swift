import Combine
import Foundation

@MainActor
protocol SessionAuthenticationProviding: AnyObject {
    var currentUserID: UUID? { get }
    func signOut() async throws
    func clearLocalSession()
}

@MainActor
protocol SessionDeviceDeactivationProviding: AnyObject {
    func unregisterCurrentDevice() async -> Bool
    func abortSignOutPreparation()
}

protocol SessionAccountDeletionProviding: Sendable {
    func deleteAccount() async throws
}

protocol SessionAccountDataExportProviding: Sendable {
    func exportAccountData() async throws -> URL
    func discardExport(at url: URL) async
}

enum SessionCoordinatorError: LocalizedError {
    case deviceDeactivationFailed
    case accountDeletionUnavailable
    case accountExportUnavailable

    var errorDescription: String? {
        switch self {
        case .deviceDeactivationFailed:
            AppStrings.localized("settings.notifications_push_setup_error")
        case .accountDeletionUnavailable:
            AppStrings.localized("settings.delete_account_error")
        case .accountExportUnavailable:
            AppStrings.localized("settings.export_data_error")
        }
    }
}

/// Owns the one sign-out sequence shared by every authenticated exit path.
@MainActor
final class SessionCoordinator: ObservableObject {
    private let authentication: any SessionAuthenticationProviding
    private let deviceDeactivation: any SessionDeviceDeactivationProviding
    private let accountDeletion: (any SessionAccountDeletionProviding)?
    private let accountDataExport: (any SessionAccountDataExportProviding)?
    private let clearPrivateState: @Sendable (UUID?) async -> Void

    init(
        authentication: any SessionAuthenticationProviding,
        deviceDeactivation: any SessionDeviceDeactivationProviding,
        accountDeletion: (any SessionAccountDeletionProviding)? = nil,
        accountDataExport: (any SessionAccountDataExportProviding)? = nil,
        clearPrivateState: @escaping @Sendable (UUID?) async -> Void = { userID in
            await ProtectedFilePlanStore.shared.removeAllAuthenticatedPlans()
            await CommunityContentCache.shared.removeAll()
            await CommunityPrivateImageCache.shared.removeAll()
            CommunityPrivateImageURLCache.shared.removeAll()
            CommunityChatBackgroundImageStore.shared.removeAll()
            if let userID {
                await CommunityMessageDraftStore.shared.removeAll(for: userID)
                await CommunityPendingImageStore.shared.removeAll(for: userID)
                await AccountDataExportFileStore.shared.removeAll(for: userID)
            } else {
                await CommunityMessageDraftStore.shared.removeAll()
                await CommunityPendingImageStore.shared.removeAll()
                await AccountDataExportFileStore.shared.removeAll()
            }
        }
    ) {
        self.authentication = authentication
        self.deviceDeactivation = deviceDeactivation
        self.accountDeletion = accountDeletion
        self.accountDataExport = accountDataExport
        self.clearPrivateState = clearPrivateState
    }

    func signOut() async throws {
        let userID = authentication.currentUserID
        let didDeactivateDevice = await deviceDeactivation.unregisterCurrentDevice()
        guard didDeactivateDevice else {
            deviceDeactivation.abortSignOutPreparation()
            throw SessionCoordinatorError.deviceDeactivationFailed
        }

        await clearPrivateState(userID)

        do {
            try await authentication.signOut()
        } catch {
            deviceDeactivation.abortSignOutPreparation()
            throw error
        }
    }

    func deleteAccount() async throws {
        guard let accountDeletion else {
            throw SessionCoordinatorError.accountDeletionUnavailable
        }

        let userID = authentication.currentUserID
        _ = await deviceDeactivation.unregisterCurrentDevice()
        do {
            try await accountDeletion.deleteAccount()
            await clearPrivateState(userID)
            try? await authentication.signOut()
            authentication.clearLocalSession()
        } catch {
            deviceDeactivation.abortSignOutPreparation()
            throw error
        }
    }

    func exportAccountData() async throws -> URL {
        guard let accountDataExport else {
            throw SessionCoordinatorError.accountExportUnavailable
        }
        return try await accountDataExport.exportAccountData()
    }

    func discardExport(at url: URL) async {
        await accountDataExport?.discardExport(at: url)
    }
}

extension AuthenticationStore: SessionAuthenticationProviding {}
extension PushNotificationsStore: SessionDeviceDeactivationProviding {}
