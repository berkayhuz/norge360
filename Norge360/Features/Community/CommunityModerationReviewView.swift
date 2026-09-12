import SwiftUI

struct CommunityModerationReviewView: View {
    @EnvironmentObject private var moderationStore: CommunityModerationStore
    @State private var selectedReport: CommunityModerationReport?

    var body: some View {
        Group {
            if moderationStore.isLoading && moderationStore.reports.isEmpty {
                NorgeLoadingState()
            } else if moderationStore.reports.isEmpty {
                NorgeUnavailableState(
                    AppStrings.localized("moderation.empty_title"),
                    systemImage: "checkmark.shield",
                    description: AppStrings.localized("moderation.empty_body")
                )
            } else {
                List(moderationStore.reports) { report in
                    Button {
                        selectedReport = report
                    } label: {
                        CommunityModerationReportRow(report: report)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.norgeAppBackground)
                    .accessibilityLabel(
                        "\(AppStrings.localized("moderation.report_target")): \(report.targetType.rawValue). "
                            + "\(AppStrings.localized("moderation.report_reason")): \(report.reason)"
                    )
                }
                .listStyle(.plain)
            }
        }
        .norgeScreen()
        .navigationTitle(AppStrings.localized("moderation.title"))
        .overlay(alignment: .top) {
            if let errorMessage = moderationStore.errorMessage {
                NorgeInlineFeedback(message: errorMessage)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
        }
        .refreshable { await moderationStore.reloadReports() }
        .task { await moderationStore.activate() }
        .sheet(item: $selectedReport) { report in
            CommunityModerationReportDetailView(report: report)
        }
    }
}

private struct CommunityModerationReportRow: View {
    let report: CommunityModerationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(report.targetType.rawValue.capitalized, systemImage: targetSymbol)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(report.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(report.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.subheadline)
            if let details = report.details, !details.isEmpty {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 5)
    }

    private var targetSymbol: String {
        switch report.targetType {
        case .profile: "person"
        case .post: "text.bubble"
        case .comment: "bubble.left"
        case .event: "calendar"
        case .group: "person.3"
        case .message: "message"
        case .groupMessage: "person.3.sequence"
        }
    }
}

private struct CommunityModerationReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var moderationStore: CommunityModerationStore

    let report: CommunityModerationReport
    @State private var enforcementAction: CommunityModerationEnforcementAction = .removeContent
    @State private var resolutionAction: CommunityReportResolutionAction = .noAction
    @State private var resolutionStatus: CommunityReportReviewStatus = .resolved
    @State private var moderationNote = ""
    @State private var memberNotice = ""
    @State private var temporaryRestriction = true
    @State private var restrictionHours = 168
    @State private var isSaving = false
    @State private var isConfirmingEnforcement = false
    @State private var isConfirmingResolution = false

    var body: some View {
        NavigationStack {
            Group {
                if moderationStore.isLoadingContext && moderationStore.context == nil {
                    ProgressView()
                } else {
                    Form {
                        reportSection
                        targetPreviewSection
                        if canEnforce {
                            enforcementSection
                        }
                        resolutionSection
                        auditSection
                    }
                }
            }
            .norgeScreen()
            .navigationTitle(AppStrings.localized("moderation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.onboardingCancel) { dismiss() }
                }
                .norgePlainToolbar()
            }
            .task(id: report.id) {
                await moderationStore.loadContext(reportID: report.id)
            }
            .onDisappear { moderationStore.clearContext() }
            .confirmationDialog(
                AppStrings.localized("moderation.confirm_enforcement"),
                isPresented: $isConfirmingEnforcement,
                titleVisibility: .visible
            ) {
                Button(enforcementAction.title, role: enforcementAction.isDestructive ? .destructive : nil) {
                    Task { await applyEnforcement() }
                }
            }
            .confirmationDialog(
                AppStrings.localized("moderation.save"),
                isPresented: $isConfirmingResolution,
                titleVisibility: .visible
            ) {
                Button(
                    resolutionStatus == .resolved
                        ? AppStrings.localized("moderation.resolve") : AppStrings.localized("moderation.dismiss")
                ) {
                    Task { await resolveReport() }
                }
            }
        }
    }

    private var reportSection: some View {
        Section(AppStrings.localized("moderation.report_reason")) {
            Text(report.reason.replacingOccurrences(of: "_", with: " ").capitalized)
            if let details = report.details, !details.isEmpty {
                Text(details)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.norgeAppBackground)
    }

    @ViewBuilder
    private var targetPreviewSection: some View {
        Section(AppStrings.localized("moderation.target_preview")) {
            if let target = moderationStore.context?.target {
                if let title = target.title ?? target.name ?? target.displayName {
                    Text(title).font(.headline)
                }
                if let username = target.username {
                    Text("@\(username)").foregroundStyle(.secondary)
                }
                if let body = target.body ?? target.details ?? target.description, !body.isEmpty {
                    Text(body)
                        .textSelection(.enabled)
                        .lineLimit(12)
                }
                if let state = target.moderationState {
                    LabeledContent(AppStrings.localized("moderation.current_state"), value: state.capitalized)
                }
                if let createdAt = target.createdAt {
                    LabeledContent(AppStrings.localized("moderation.created")) {
                        Text(createdAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
            } else {
                Text(AppStrings.localized("moderation.target_unavailable"))
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.norgeAppBackground)
    }

    private var enforcementSection: some View {
        Section(AppStrings.localized("moderation.enforcement")) {
            Picker(AppStrings.localized("moderation.action"), selection: $enforcementAction) {
                ForEach(CommunityModerationEnforcementAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }

            if enforcementAction == .restrictAuthor {
                Toggle(AppStrings.localized("moderation.temporary_restriction"), isOn: $temporaryRestriction)
                if temporaryRestriction {
                    Stepper(value: $restrictionHours, in: 1...8_760) {
                        Text(String(format: AppStrings.localized("moderation.restriction_duration"), restrictionHours))
                    }
                }
            }

            TextField(AppStrings.localized("moderation.enforcement_audit_note"), text: $moderationNote, axis: .vertical)
                .lineLimit(3...8)
            TextField(AppStrings.localized("moderation.member_notice"), text: $memberNotice, axis: .vertical)
                .lineLimit(3...6)
            Text(AppStrings.localized("moderation.member_notice_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(enforcementAction.title, role: enforcementAction.isDestructive ? .destructive : nil) {
                isConfirmingEnforcement = true
            }
            .disabled(
                isSaving || moderationNote.count > 1_000 || memberNotice.count > 500
                    || moderationStore.context?.target == nil)
        }
        .listRowBackground(Color.norgeAppBackground)
    }

    private var resolutionSection: some View {
        Section(AppStrings.localized("moderation.resolution")) {
            Picker(AppStrings.localized("moderation.action"), selection: $resolutionAction) {
                ForEach(CommunityReportResolutionAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            Picker(AppStrings.localized("moderation.title"), selection: $resolutionStatus) {
                Text(AppStrings.localized("moderation.status_resolved")).tag(CommunityReportReviewStatus.resolved)
                Text(AppStrings.localized("moderation.status_dismissed")).tag(CommunityReportReviewStatus.dismissed)
            }
            Button(
                resolutionStatus == .resolved
                    ? AppStrings.localized("moderation.resolve") : AppStrings.localized("moderation.dismiss")
            ) {
                isConfirmingResolution = true
            }
            .disabled(isSaving)
        }
        .listRowBackground(Color.norgeAppBackground)
    }

    @ViewBuilder
    private var auditSection: some View {
        if let actions = moderationStore.context?.actions, !actions.isEmpty {
            Section(AppStrings.localized("moderation.audit_history")) {
                ForEach(actions) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.action.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline.weight(.semibold))
                        if let note = action.note, !note.isEmpty {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(action.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(Color.norgeAppBackground)
        }
    }

    private var canEnforce: Bool {
        guard moderationStore.role != .reviewer else { return false }
        return switch report.targetType {
        case .profile, .post, .comment, .group, .groupMessage: true
        case .event, .message: false
        }
    }

    private func applyEnforcement() async {
        isSaving = true
        defer { isSaving = false }
        _ = await moderationStore.apply(
            reportID: report.id,
            action: enforcementAction,
            note: moderationNote.nilIfBlank,
            memberNotice: memberNotice.nilIfBlank,
            restrictionHours: enforcementAction == .restrictAuthor && temporaryRestriction ? restrictionHours : nil
        )
    }

    private func resolveReport() async {
        isSaving = true
        defer { isSaving = false }
        if await moderationStore.resolve(
            reportID: report.id,
            status: resolutionStatus,
            action: resolutionAction,
            note: moderationNote.nilIfBlank
        ) {
            dismiss()
        }
    }
}

extension CommunityReportResolutionAction {
    fileprivate var title: String { AppStrings.localized("moderation.action.\(rawValue)") }
}

extension CommunityModerationEnforcementAction {
    fileprivate var title: String { AppStrings.localized("moderation.enforcement.\(rawValue)") }
    fileprivate var isDestructive: Bool { self == .removeContent || self == .restrictAuthor }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
