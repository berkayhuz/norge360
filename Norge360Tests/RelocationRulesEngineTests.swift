import XCTest

@testable import Norge360

final class RelocationRulesEngineTests: XCTestCase {
    private let engine = RelocationRulesEngine()

    func testNonEEAWorkProfileReceivesResidencePermitGuidance() {
        let profile = makeProfile(isEEA: false, reason: .work, household: .alone)
        XCTAssertTrue(engine.makeTasks(for: profile).contains { $0.slug == "residence-permit-work" })
    }

    func testNonEEAReasonsReceiveDedicatedOfficialGuidance() {
        let reasons: [(MovingReason, String)] = [
            (.study, "residence-permit-study"),
            (.familyImmigration, "residence-permit-family"),
            (.selfEmployment, "residence-permit-self-employment"),
            (.other, "immigration-general-guidance"),
        ]

        for (reason, expectedSlug) in reasons {
            let profile = makeProfile(isEEA: false, reason: reason, household: .alone)
            let task = engine.makeTasks(for: profile).first { $0.slug == expectedSlug }
            XCTAssertNotNil(task)
            XCTAssertNotNil(task?.officialSource.url)
        }
    }

    func testCurrentStatusStayDurationAndJobOfferChangeGuidance() {
        let profile = RelocationProfile(
            citizenship: "Canada", isEEACitizen: false, currentlyInNorway: true,
            movingReason: .work, stayDuration: .threeToTwelveMonths,
            destinationCity: "Oslo", householdType: .alone, hasJobOffer: false)
        let slugs = Set(engine.makeTasks(for: profile).map(\.slug))

        XCTAssertTrue(slugs.contains("nationality-specific-guidance"))
        XCTAssertTrue(slugs.contains("stay-duration-guidance"))
        XCTAssertTrue(slugs.contains("current-norway-status-guidance"))
        XCTAssertTrue(slugs.contains("work-offer-guidance"))
    }

    func testEmptyCitizenshipDoesNotCreateNationalitySpecificTask() {
        let profile = RelocationProfile(
            citizenship: "  ", isEEACitizen: true, currentlyInNorway: false,
            movingReason: .study, stayDuration: .underThreeMonths,
            destinationCity: "Oslo", householdType: .alone, hasJobOffer: false)

        XCTAssertFalse(engine.makeTasks(for: profile).contains { $0.slug == "nationality-specific-guidance" })
    }

    func testHouseholdWithChildrenReceivesChildrenGuidance() {
        let profile = makeProfile(isEEA: true, reason: .study, household: .partnerAndChildren)
        XCTAssertTrue(engine.makeTasks(for: profile).contains { $0.slug == "school-kindergarten-guidance" })
    }

    func testCompletedTaskChangesPlanProgress() {
        let profile = makeProfile(isEEA: true, reason: .work, household: .alone)
        var plan = RelocationPlan(profile: profile, tasks: engine.makeTasks(for: profile))
        plan.tasks[0].setStatus(.completed)
        XCTAssertEqual(plan.completedCount, 1)
        XCTAssertEqual(plan.progressFraction, 1.0 / Double(plan.tasks.count), accuracy: 0.0001)
        XCTAssertEqual(PlanProgress.completedTasks(in: plan.tasks), 1)
    }

    func testTaskDefinitionsUseLocalizationKeysAndVersionedContent() throws {
        let profile = makeProfile(isEEA: true, reason: .work, household: .alone)
        let task = try XCTUnwrap(engine.makeTasks(for: profile).first { $0.slug == "tax-card-guidance" })

        XCTAssertEqual(task.definition.titleKey, "task.tax_card.title")
        XCTAssertEqual(task.definition.taskDescriptionKey, "task.tax_card.description")
        XCTAssertEqual(task.definition.contentVersion, RelocationTaskDefinition.currentContentVersion)
        XCTAssertEqual(task.definition.rulesVersion, RelocationTaskDefinition.currentRulesVersion)
    }

    func testRebuildingTasksPreservesProgressCompletionDateAndStableID() throws {
        let profile = makeProfile(isEEA: true, reason: .work, household: .alone)
        var existingTasks = engine.makeTasks(for: profile)
        let taskIndex = try XCTUnwrap(existingTasks.firstIndex { $0.slug == "tax-card-guidance" })
        let originalID = existingTasks[taskIndex].id
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        existingTasks[taskIndex].setStatus(.completed, now: completedAt)

        let rebuiltTasks = engine.makeTasks(for: profile, preserving: existingTasks)
        let rebuiltTask = try XCTUnwrap(rebuiltTasks.first { $0.slug == "tax-card-guidance" })

        XCTAssertEqual(rebuiltTask.id, originalID)
        XCTAssertEqual(rebuiltTask.status, .completed)
        XCTAssertEqual(rebuiltTask.completedAt, completedAt)
    }

    func testLongStayReceivesOfficialMoveAndIdentityGuidance() {
        let profile = makeProfile(isEEA: true, reason: .study, household: .alone)
        let tasks = engine.makeTasks(for: profile)

        XCTAssertTrue(tasks.contains { $0.slug == "report-move-guidance" })
        XCTAssertTrue(tasks.contains { $0.slug == "identity-number-guidance" })
        XCTAssertNotNil(tasks.first(where: { $0.slug == "report-move-guidance" })?.officialSource.url)
    }

    func testShortStayDoesNotReceiveLongStayRegistrationGuidance() {
        var profile = makeProfile(isEEA: true, reason: .study, household: .alone)
        profile = RelocationProfile(
            citizenship: profile.citizenship, isEEACitizen: profile.isEEACitizen,
            currentlyInNorway: profile.currentlyInNorway, movingReason: profile.movingReason,
            stayDuration: .underThreeMonths, destinationCity: profile.destinationCity,
            householdType: profile.householdType, hasJobOffer: profile.hasJobOffer)

        let slugs = engine.makeTasks(for: profile).map(\.slug)
        XCTAssertFalse(slugs.contains("report-move-guidance"))
        XCTAssertFalse(slugs.contains("identity-number-guidance"))
    }

    func testSupportedDestinationReceivesVerifiedMunicipalTask() {
        let profile = makeProfile(isEEA: true, reason: .study, household: .alone)
        let cityTask = engine.makeTasks(for: profile).first { $0.slug == "city-services-oslo" }

        XCTAssertEqual(cityTask?.officialSource.name, "City of Oslo — Key information sources")
        XCTAssertNotNil(cityTask?.officialSource.url)
    }

    func testOtherMunicipalityDoesNotReceiveAnUnverifiedCityTask() {
        let profile = RelocationProfile(
            citizenship: "Canada", isEEACitizen: true, currentlyInNorway: false,
            movingReason: .study, stayDuration: .moreThanTwelveMonths,
            destinationCity: "Ålesund", householdType: .alone, hasJobOffer: false)
        XCTAssertFalse(engine.makeTasks(for: profile).contains { $0.slug.hasPrefix("city-services-") })
    }

    private func makeProfile(isEEA: Bool, reason: MovingReason, household: HouseholdType) -> RelocationProfile {
        RelocationProfile(
            citizenship: "Canada", isEEACitizen: isEEA, currentlyInNorway: false,
            movingReason: reason, stayDuration: .moreThanTwelveMonths,
            destinationCity: "Oslo", householdType: household, hasJobOffer: true)
    }
}
