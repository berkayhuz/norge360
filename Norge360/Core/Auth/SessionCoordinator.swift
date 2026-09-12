import Combine
import Foundation

@MainActor
protocol SessionAuthenticationProviding: AnyObject {
    func signOut() async throws
}

@MainActor
protocol SessionDeviceDeactivationProviding: AnyObject {
    func unregisterCurrentDevice() async -> Bool
    func abortSignOutPreparation()
}

enum SessionCoordinatorError: LocalizedError {
    case deviceDeactivationFailed

    var errorDescription: String? {
        AppStrings.localized("settings.notifications_push_setup_error")
    }
}

/// Owns the one sign-out sequence shared by every authenticated exit path.
@MainActor
final class SessionCoordinator: ObservableObject {
    private let authentication: any SessionAuthenticationProviding
    private let deviceDeactivation: any SessionDeviceDeactivationProviding
    private let clearPrivateState: @Sendable () async -> Void

    init(
        authentication: any SessionAuthenticationProviding,
        deviceDeactivation: any SessionDeviceDeactivationProviding,
        clearPrivateState: @escaping @Sendable () async -> Void = {
            await ProtectedFilePlanStore.shared.removeAllAuthenticatedPlans()
            await CommunityContentCache.shared.removeAll()
            await CommunityPrivateImageCache.shared.removeAll()
            await CommunityPrivateImageURLCache.shared.removeAll()
            await CommunityChatBackgroundImageStore.shared.removeAll()
        }
    ) {
        self.authentication = authentication
        self.deviceDeactivation = deviceDeactivation
        self.clearPrivateState = clearPrivateState
    }

    func signOut() async throws {
        let didDeactivateDevice = await deviceDeactivation.unregisterCurrentDevice()
        await clearPrivateState()

        do {
            try await authentication.signOut()
        } catch {
            deviceDeactivation.abortSignOutPreparation()
            throw error
        }

        guard didDeactivateDevice else {
            throw SessionCoordinatorError.deviceDeactivationFailed
        }
    }
}

extension AuthenticationStore: SessionAuthenticationProviding {}
extension PushNotificationsStore: SessionDeviceDeactivationProviding {}
