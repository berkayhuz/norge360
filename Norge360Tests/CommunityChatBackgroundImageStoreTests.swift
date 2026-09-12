import XCTest

@testable import Norge360

final class CommunityChatBackgroundImageStoreTests: XCTestCase {
    func testImagesAreScopedByUserAndConversation() async throws {
        let context = try makeStore()
        let firstUser = UUID()
        let secondUser = UUID()
        let conversation = UUID()
        let data = Data([1, 2, 3])

        await context.store.save(data, for: conversation, userID: firstUser)

        let firstUserData = await context.store.imageData(for: conversation, userID: firstUser)
        let secondUserData = await context.store.imageData(for: conversation, userID: secondUser)

        XCTAssertEqual(firstUserData, data)
        XCTAssertNil(secondUserData)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: context.directory
                    .appendingPathComponent(firstUser.uuidString.lowercased(), isDirectory: true)
                    .appendingPathComponent(conversation.uuidString.lowercased() + ".jpg")
                    .path
            )
        )
    }

    func testProtectedFileIsExcludedFromBackup() async throws {
        let context = try makeStore()
        let userID = UUID()
        let conversationID = UUID()

        await context.store.save(Data([1, 2, 3]), for: conversationID, userID: userID)

        let fileURL = context.directory
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(conversationID.uuidString.lowercased() + ".jpg")
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .complete)
        }
        let resourceValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)
    }

    func testQuotaRemovesOldestBackground() async throws {
        let context = try makeStore(maxItemCount: 1, maxTotalBytes: 10)
        let userID = UUID()
        let firstConversation = UUID()
        let secondConversation = UUID()

        await context.store.save(Data([1]), for: firstConversation, userID: userID)
        let firstURL = context.directory
            .appendingPathComponent(userID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(firstConversation.uuidString.lowercased() + ".jpg")
        try FileManager.default.setAttributes(
            [.modificationDate: Date.distantPast],
            ofItemAtPath: firstURL.path
        )
        await context.store.save(Data([2]), for: secondConversation, userID: userID)

        let firstData = await context.store.imageData(for: firstConversation, userID: userID)
        let secondData = await context.store.imageData(for: secondConversation, userID: userID)

        XCTAssertNil(firstData)
        XCTAssertEqual(secondData, Data([2]))
    }

    func testRemoveAllPurgesEveryAccountNamespace() async throws {
        let context = try makeStore()
        let firstUser = UUID()
        let secondUser = UUID()

        await context.store.save(Data([1]), for: UUID(), userID: firstUser)
        await context.store.save(Data([2]), for: UUID(), userID: secondUser)
        await context.store.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: context.directory.path))
    }

    func testLegacyUnscopedFileIsNeverRead() async throws {
        let context = try makeStore()
        let conversationID = UUID()
        try FileManager.default.createDirectory(at: context.directory, withIntermediateDirectories: true)
        try Data([9]).write(
            to: context.directory.appendingPathComponent(conversationID.uuidString.lowercased() + ".jpg")
        )

        let loaded = await context.store.imageData(for: conversationID, userID: UUID())

        XCTAssertNil(loaded)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: context.directory.appendingPathComponent(conversationID.uuidString.lowercased() + ".jpg").path
            )
        )
    }

    private struct StoreContext {
        let store: CommunityChatBackgroundImageStore
        let directory: URL
    }

    private func makeStore(maxItemCount: Int = 40, maxTotalBytes: Int = 20 * 1024 * 1024) throws -> StoreContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Norge360ChatBackgrounds.\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return StoreContext(
            store: CommunityChatBackgroundImageStore(
                directory: directory,
                maxItemCount: maxItemCount,
                maxTotalBytes: maxTotalBytes
            ),
            directory: directory
        )
    }
}
