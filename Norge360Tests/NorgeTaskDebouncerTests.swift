import XCTest

@testable import Norge360

final class NorgeTaskDebouncerTests: XCTestCase {
    func testLatestScheduledOperationReplacesEarlierOperation() async throws {
        let debouncer = await MainActor.run { NorgeTaskDebouncer() }
        let result = await MainActor.run { DebounceResult() }

        await MainActor.run {
            debouncer.schedule(after: .milliseconds(80)) {
                result.values.append("first")
            }
            debouncer.schedule(after: .milliseconds(10)) {
                result.values.append("second")
            }
        }

        try await Task.sleep(for: .milliseconds(120))
        let values = await MainActor.run { result.values }
        XCTAssertEqual(values, ["second"])
    }

    func testCancelPreventsPendingOperation() async throws {
        let debouncer = await MainActor.run { NorgeTaskDebouncer() }
        let result = await MainActor.run { DebounceResult() }

        await MainActor.run {
            debouncer.schedule(after: .milliseconds(40)) {
                result.values.append("unexpected")
            }
            debouncer.cancel()
        }

        try await Task.sleep(for: .milliseconds(80))
        let values = await MainActor.run { result.values }
        XCTAssertTrue(values.isEmpty)
    }
}

@MainActor
private final class DebounceResult {
    var values: [String] = []
}
