import Foundation

@MainActor
final class CommunityModerationStore: ObservableObject {
    @Published private(set) var role: CommunityModeratorRole?
    @Published private(set) var reports: [CommunityModerationReport] = []
    @Published private(set) var isCheckingRole = false
    @Published private(set) var roleCheckFailed = false
    @Published private(set) var roleCheckDiagnostic: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var context: CommunityModerationReportContext?
    @Published private(set) var isLoadingContext = false

    private let service: any CommunityModerationProviding
    private var activeUserID: UUID?
    private var roleTask: Task<Void, Never>?
    private var reportsTask: Task<Void, Never>?
    private var contextTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var contextGeneration = 0

    init(service: any CommunityModerationProviding) {
        self.service = service
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser?) {
        guard activeUserID != user?.id else { return }
        activeUserID = user?.id
        roleTask?.cancel()
        roleTask = nil
        reportsTask?.cancel()
        reportsTask = nil
        contextTask?.cancel()
        contextTask = nil
        loadGeneration &+= 1
        contextGeneration &+= 1
        role = nil
        reports = []
        context = nil
        errorMessage = nil
        roleCheckFailed = false
        roleCheckDiagnostic = nil
        isCheckingRole = false
        isLoading = false
        isLoadingContext = false
    }

    /// Authorization is checked when a moderation surface is opened, not at
    /// every authentication transition.
    func activate() async {
        guard activeUserID != nil else { return }
        if role == nil && !isCheckingRole {
            await refreshRole()
        }
        if role != nil, reports.isEmpty, !isLoading {
            await reloadReports()
        }
    }

    func refreshRole() async {
        guard let userID = activeUserID else { return }
        if let roleTask {
            await roleTask.value
            return
        }
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await performRoleRefresh(userID: userID, generation: generation)
            if loadGeneration == generation { roleTask = nil }
        }
        roleTask = task
        await task.value
    }

    func reloadReports() async {
        guard role != nil, let userID = activeUserID else { return }
        if let reportsTask {
            await reportsTask.value
            return
        }
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await performReportsReload(userID: userID, generation: generation)
            if loadGeneration == generation { reportsTask = nil }
        }
        reportsTask = task
        await task.value
    }

    func loadContext(reportID: UUID) async {
        guard let userID = activeUserID else { return }
        contextTask?.cancel()
        contextGeneration &+= 1
        let contextGeneration = contextGeneration
        let generation = loadGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            isLoadingContext = true
            errorMessage = nil
            defer {
                if loadGeneration == generation, self.contextGeneration == contextGeneration {
                    isLoadingContext = false
                }
            }
            do {
                let loadedContext = try await service.loadContext(reportID: reportID)
                guard activeUserID == userID, loadGeneration == generation,
                    self.contextGeneration == contextGeneration, !Task.isCancelled
                else { return }
                context = loadedContext
            } catch is CancellationError {
                // A context load is cancelled when the moderator changes account or report.
            } catch {
                guard activeUserID == userID, loadGeneration == generation,
                    self.contextGeneration == contextGeneration, !Task.isCancelled
                else { return }
                context = nil
                errorMessage = AppStrings.localized("moderation.context_error")
            }
        }
        contextTask = task
        await task.value
        if loadGeneration == generation, self.contextGeneration == contextGeneration { contextTask = nil }
    }

    private func performRoleRefresh(userID: UUID, generation: Int) async {
        isCheckingRole = true
        roleCheckFailed = false
        roleCheckDiagnostic = nil
        defer {
            if loadGeneration == generation { isCheckingRole = false }
        }
        do {
            let loadedRole = try await service.loadRole()
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            role = loadedRole
        } catch {
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            // Normal members receive `nil` for an authorization denial. A true
            // network/configuration failure is retained so staff can retry.
            role = nil
            roleCheckFailed = true
            if case CommunityModerationServiceError.remoteStatus(let status) = error {
                roleCheckDiagnostic = "HTTP \(status)"
            } else {
                roleCheckDiagnostic = "Connection error"
            }
        }
    }

    private func performReportsReload(userID: UUID, generation: Int) async {
        if reports.isEmpty { isLoading = true }
        errorMessage = nil
        defer {
            if loadGeneration == generation { isLoading = false }
        }
        do {
            let loadedReports = try await service.loadOpenReports()
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            reports = loadedReports
        } catch is CancellationError {
            // A report reload is cancelled on account change or view deactivation.
        } catch {
            guard activeUserID == userID, loadGeneration == generation, !Task.isCancelled else { return }
            errorMessage = AppStrings.localized("moderation.error")
        }
    }

    func clearContext() {
        context = nil
    }

    func resolve(
        reportID: UUID,
        status: CommunityReportReviewStatus,
        action: CommunityReportResolutionAction,
        note: String?
    ) async -> Bool {
        guard let index = reports.firstIndex(where: { $0.id == reportID }) else { return false }
        let removed = reports.remove(at: index)
        do {
            try await service.resolve(reportID: reportID, status: status, action: action, note: note)
            return true
        } catch {
            reports.insert(removed, at: index)
            errorMessage = AppStrings.localized("moderation.error")
            return false
        }
    }

    func apply(
        reportID: UUID,
        action: CommunityModerationEnforcementAction,
        note: String?,
        memberNotice: String?,
        restrictionHours: Int?
    ) async -> Bool {
        do {
            try await service.apply(
                reportID: reportID,
                action: action,
                note: note,
                memberNotice: memberNotice,
                restrictionHours: restrictionHours
            )
            await loadContext(reportID: reportID)
            return context != nil
        } catch {
            errorMessage = AppStrings.localized("moderation.action_error")
            return false
        }
    }
}
