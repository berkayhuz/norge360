import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushNotificationsStore: ObservableObject {
    @Published private(set) var messagePushEnabled = true
    @Published private(set) var registrationErrorMessage: String?

    private let service: any CommunityPushNotificationsProviding
    private var activeUserID: UUID?
    private var currentDeviceToken: String?
    private var registrationTask: Task<Void, Never>?
    private var isPreparingForSignOut = false
    // NotificationCenter tokens are only touched on the main actor and during
    // teardown. The unsafe marker is required because Swift's deinit is
    // nonisolated while NSObjectProtocol is not Sendable.
    nonisolated(unsafe) private var deviceTokenObserver: NSObjectProtocol?
    nonisolated(unsafe) private var registrationFailureObserver: NSObjectProtocol?

    init(service: any CommunityPushNotificationsProviding) {
        self.service = service
        deviceTokenObserver = NotificationCenter.default.addObserver(
            forName: .norge360DidReceiveAPNSToken,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let token = notification.object as? String else { return }
            Task { @MainActor in await self?.receiveDeviceToken(token) }
        }
        registrationFailureObserver = NotificationCenter.default.addObserver(
            forName: .norge360DidFailAPNSRegistration,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let error = notification.object as? Error else { return }
            Task { @MainActor in self?.receiveRegistrationFailure(error) }
        }
    }

    deinit {
        registrationTask?.cancel()
        if let deviceTokenObserver {
            NotificationCenter.default.removeObserver(deviceTokenObserver)
        }
        if let registrationFailureObserver {
            NotificationCenter.default.removeObserver(registrationFailureObserver)
        }
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        registrationTask?.cancel()
        registrationTask = nil
        activeUserID = user?.id
        if user != nil { isPreparingForSignOut = false }
        guard user != nil else {
            messagePushEnabled = true
            registrationErrorMessage = nil
            return
        }
        registrationTask = Task { [weak self] in
            guard let self else { return }
            await loadPreference()
            await requestAuthorizationAndRegisterWithAPNs()
            await registerCurrentTokenIfPossible()
        }
    }

    func unregisterCurrentDevice() async -> Bool {
        isPreparingForSignOut = true
        registrationTask?.cancel()
        registrationTask = nil
        guard let currentDeviceToken, activeUserID != nil else { return true }

        for attempt in 0..<2 {
            do {
                try await service.deactivate(deviceToken: currentDeviceToken)
                return true
            } catch {
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(250)) }
            }
        }
        return false
    }

    func abortSignOutPreparation() {
        isPreparingForSignOut = false
        Task { await registerCurrentTokenIfPossible() }
    }

    func updateMessagePushEnabled(_ enabled: Bool) async throws {
        try await service.updateMessagePushEnabled(enabled)
        messagePushEnabled = enabled
        if enabled {
            await retryRegistration()
        }
    }

    func retryRegistration() async {
        guard !isPreparingForSignOut, activeUserID != nil, messagePushEnabled else { return }
        registrationErrorMessage = nil
        await requestAuthorizationAndRegisterWithAPNs()
        await registerCurrentTokenIfPossible()
    }

    private func loadPreference() async {
        messagePushEnabled = (try? await service.loadMessagePushEnabled()) ?? true
    }

    private func requestAuthorizationAndRegisterWithAPNs() async {
        guard messagePushEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
        guard isAuthorized else {
            registrationErrorMessage = AppStrings.localized("settings.notifications_push_permission_required")
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func receiveDeviceToken(_ token: String) async {
        currentDeviceToken = token
        await registerCurrentTokenIfPossible()
    }

    private func registerCurrentTokenIfPossible() async {
        guard !isPreparingForSignOut, activeUserID != nil, messagePushEnabled, let currentDeviceToken else { return }
        do {
            try await service.register(deviceToken: currentDeviceToken, environment: .current)
            registrationErrorMessage = nil
        } catch {
            registrationErrorMessage = pushRegistrationError(for: error)
        }
    }

    private func receiveRegistrationFailure(_ error: Error) {
        registrationErrorMessage = pushRegistrationError(for: error)
    }

    private func pushRegistrationError(for error: Error) -> String {
        #if DEBUG
            return "Debug APNs registration error: \(error.localizedDescription)"
        #else
            return AppStrings.localized("settings.notifications_push_setup_error")
        #endif
    }
}

extension CommunityPushEnvironment {
    fileprivate static var current: Self {
        let configuredValue = Bundle.main.object(forInfoDictionaryKey: "Norge360PushEnvironment") as? String
        return Self(rawValue: configuredValue ?? "") ?? .development
    }
}
