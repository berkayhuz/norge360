import XCTest

@testable import Norge360

final class RelocationRulesEngineTests: XCTestCase {
    private let engine = RelocationRulesEngine()

    func testNonEEAWorkProfileReceivesResidencePermitGuidance() {
        let profile = makeProfile(isEEA: false, reason: .work, household: .alone)
        XCTAssertTrue(engine.makeTasks(for: profile).contains { $0.slug == "residence-permit-work" })
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
