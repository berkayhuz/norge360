import XCTest

@testable import Norge360

final class AccountDataExportFileStoreTests: XCTestCase {
    func testOwnerPurgeRemovesOnlyThatOwnersExport() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("norge360-export-test-\(UUID().uuidString)", isDirectory: true)
        let store = AccountDataExportFileStore(rootDirectory: rootDirectory)
        let firstOwner = UUID()
        let secondOwner = UUID()

        let firstURL = try await store.write(Data("first".utf8), ownerID: firstOwner)
        let secondURL = try await store.write(Data("second".utf8), ownerID: secondOwner)

        await store.removeAll(for: firstOwner)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))

        await store.removeAll(for: secondOwner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func testDownloadedExportIsMovedIntoProtectedOwnerScope() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("norge360-export-download-test-\(UUID().uuidString)", isDirectory: true)
        let store = AccountDataExportFileStore(rootDirectory: rootDirectory)
        let ownerID = UUID()
        let temporaryURL = rootDirectory.appendingPathComponent("download.tmp")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Data("{\"schema_version\":1}".utf8).write(to: temporaryURL)

        let exportURL = try await store.moveDownloadedFile(at: temporaryURL, ownerID: ownerID)

        XCTAssertTrue(exportURL.path.contains(ownerID.uuidString.lowercased()))
        XCTAssertEqual(try Data(contentsOf: exportURL), Data("{\"schema_version\":1}".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
