import Foundation

/// A deliberately conservative, deterministic routing engine.
/// It directs users to official guidance; it never determines legal eligibility.
struct RelocationRulesEngine: Sendable {
    func makeTasks(for profile: RelocationProfile) -> [RelocationTask] {
        var tasks: [RelocationTask] = []

        // More than twelve months is safely within the official page's six-month threshold.
        if profile.stayDuration == .moreThanTwelveMonths {
            tasks.append(reportMoveTask())
            tasks.append(identityGuidanceTask())
        }

        // This is guidance for people planning employee work, not a tax-liability determination.
        if profile.movingReason == .work {
            tasks.append(taxCardGuidanceTask())
        }

        if !profile.isEEACitizen && profile.movingReason == .work {
            tasks.append(residencePermitGuidanceTask())
        }
        if profile.householdType.includesChildren {
            tasks.append(childrenGuidanceTask())
        }
        if let cityTask = CityResourceCatalog.task(for: profile.destinationCity) {
            tasks.append(cityTask)
        }
        return tasks.sorted { $0.priority < $1.priority }
    }

    private func reportMoveTask() -> RelocationTask {
        RelocationTask(
            slug: "report-move-guidance", title: AppStrings.taskReportMove,
            taskDescription: AppStrings.taskReportMoveDescription,
            category: .arrival, priority: 10,
            officialSource: OfficialSourceCatalog.reportMoveToNorway,
            regulatoryDisclaimer: AppStrings.regulatoryDisclaimer)
    }

    private func identityGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "identity-number-guidance", title: AppStrings.taskIdentity,
            taskDescription: AppStrings.taskIdentityDescription,
            category: .identity, priority: 20, officialSource: OfficialSourceCatalog.identificationNumbers,
            regulatoryDisclaimer: AppStrings.regulatoryDisclaimer)
    }

    private func taxCardGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "tax-card-guidance", title: AppStrings.taskTaxCard,
            taskDescription: AppStrings.taskTaxCardDescription,
            category: .employment, priority: 30,
            officialSource: OfficialSourceCatalog.taxDeductionCardForForeignWorkers,
            regulatoryDisclaimer: AppStrings.regulatoryDisclaimer)
    }

    private func residencePermitGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "residence-permit-work", title: AppStrings.taskResidencePermit,
            taskDescription: AppStrings.taskResidencePermitDescription,
            category: .immigration, priority: 5, officialSource: OfficialSourceCatalog.udiWorkImmigration,
            regulatoryDisclaimer: AppStrings.regulatoryDisclaimer)
    }

    private func childrenGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "school-kindergarten-guidance", title: AppStrings.taskChildren,
            taskDescription: AppStrings.taskChildrenDescription,
            category: .family, priority: 40, officialSource: OfficialSourceCatalog.educationForNewlyArrivedFamilies,
            regulatoryDisclaimer: AppStrings.regulatoryDisclaimer)
    }
}
