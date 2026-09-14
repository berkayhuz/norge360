import Foundation

/// A deliberately conservative, deterministic routing engine.
/// It directs users to official guidance; it never determines legal eligibility.
struct RelocationRulesEngine: Sendable {
    func makeTasks(for profile: RelocationProfile, preserving existingTasks: [RelocationTask] = []) -> [RelocationTask]
    {
        let existingTasksBySlug = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.slug, $0) })
        return candidateTasks(for: profile)
            .map { task in
                guard let existingTask = existingTasksBySlug[task.slug] else { return task }
                return task.replacingID(existingTask.id).withProgress(from: existingTask)
            }
            .sorted { $0.priority < $1.priority }
    }

    private func candidateTasks(for profile: RelocationProfile) -> [RelocationTask] {
        baseGuidanceTasks(for: profile)
            + employmentTasks(for: profile)
            + immigrationTasks(for: profile)
            + contextTasks(for: profile)
    }

    private func baseGuidanceTasks(for profile: RelocationProfile) -> [RelocationTask] {
        var tasks: [RelocationTask] = []
        if !profile.citizenship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tasks.append(nationalityGuidanceTask())
        }

        // More than twelve months is safely within the official page's six-month threshold.
        if profile.stayDuration == .moreThanTwelveMonths {
            tasks.append(reportMoveTask())
            tasks.append(identityGuidanceTask())
        }

        if profile.stayDuration == .threeToTwelveMonths {
            tasks.append(stayDurationGuidanceTask())
        }
        return tasks
    }

    private func employmentTasks(for profile: RelocationProfile) -> [RelocationTask] {
        guard profile.movingReason == .work else { return [] }
        var tasks = [taxCardGuidanceTask()]
        // This is guidance for people planning employee work, not a tax-liability determination.
        if !profile.hasJobOffer {
            tasks.append(workOfferGuidanceTask())
        }
        return tasks
    }

    private func immigrationTasks(for profile: RelocationProfile) -> [RelocationTask] {
        guard !profile.isEEACitizen else { return [] }
        switch profile.movingReason {
        case .work:
            return [residencePermitGuidanceTask()]
        case .study:
            return [
                reasonSpecificImmigrationTask(
                    slug: "residence-permit-study", source: OfficialSourceCatalog.udiStudyPermit)
            ]
        case .familyImmigration:
            return [
                reasonSpecificImmigrationTask(
                    slug: "residence-permit-family", source: OfficialSourceCatalog.udiFamilyImmigration)
            ]
        case .selfEmployment:
            return [
                reasonSpecificImmigrationTask(
                    slug: "residence-permit-self-employment", source: OfficialSourceCatalog.udiSelfEmployment)
            ]
        case .other:
            return [generalImmigrationGuidanceTask()]
        }
    }

    private func contextTasks(for profile: RelocationProfile) -> [RelocationTask] {
        var tasks: [RelocationTask] = []
        if profile.currentlyInNorway {
            tasks.append(currentStatusGuidanceTask())
        }
        if profile.householdType.includesChildren {
            tasks.append(childrenGuidanceTask())
        }
        if let cityTask = CityResourceCatalog.task(for: profile.destinationCity) {
            tasks.append(cityTask)
        }
        return tasks
    }

    private func reportMoveTask() -> RelocationTask {
        RelocationTask(
            slug: "report-move-guidance", titleKey: "task.report_move.title",
            taskDescriptionKey: "task.report_move.description",
            category: .arrival, priority: 10,
            officialSource: OfficialSourceCatalog.reportMoveToNorway,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func nationalityGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "nationality-specific-guidance", titleKey: "task.nationality.title",
            taskDescriptionKey: "task.nationality.description",
            category: .immigration, priority: 2, officialSource: OfficialSourceCatalog.udiWantToApply,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func stayDurationGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "stay-duration-guidance", titleKey: "task.stay_duration.title",
            taskDescriptionKey: "task.stay_duration.description",
            category: .arrival, priority: 8, officialSource: OfficialSourceCatalog.udiWantToApply,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func currentStatusGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "current-norway-status-guidance", titleKey: "task.current_status.title",
            taskDescriptionKey: "task.current_status.description",
            category: .arrival, priority: 12, officialSource: OfficialSourceCatalog.udiWantToApply,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func identityGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "identity-number-guidance", titleKey: "task.identity.title",
            taskDescriptionKey: "task.identity.description",
            category: .identity, priority: 20, officialSource: OfficialSourceCatalog.identificationNumbers,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func taxCardGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "tax-card-guidance", titleKey: "task.tax_card.title",
            taskDescriptionKey: "task.tax_card.description",
            category: .employment, priority: 30,
            officialSource: OfficialSourceCatalog.taxDeductionCardForForeignWorkers,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func workOfferGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "work-offer-guidance", titleKey: "task.work_offer.title",
            taskDescriptionKey: "task.work_offer.description",
            category: .employment, priority: 35, officialSource: OfficialSourceCatalog.udiWorkImmigration,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func residencePermitGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "residence-permit-work", titleKey: "task.residence_permit.title",
            taskDescriptionKey: "task.residence_permit.description",
            category: .immigration, priority: 5, officialSource: OfficialSourceCatalog.udiWorkImmigration,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func reasonSpecificImmigrationTask(slug: String, source: OfficialSource) -> RelocationTask {
        RelocationTask(
            slug: slug, titleKey: "task.immigration_reason.title",
            taskDescriptionKey: "task.immigration_reason.description",
            category: .immigration, priority: 5, officialSource: source,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }

    private func generalImmigrationGuidanceTask() -> RelocationTask {
        reasonSpecificImmigrationTask(
            slug: "immigration-general-guidance", source: OfficialSourceCatalog.udiWantToApply)
    }

    private func childrenGuidanceTask() -> RelocationTask {
        RelocationTask(
            slug: "school-kindergarten-guidance", titleKey: "task.children.title",
            taskDescriptionKey: "task.children.description",
            category: .family, priority: 40, officialSource: OfficialSourceCatalog.educationForNewlyArrivedFamilies,
            regulatoryDisclaimerKey: "task.regulatory_disclaimer")
    }
}
