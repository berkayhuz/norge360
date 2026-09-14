import Foundation
import XCTest

@testable import Norge360

final class CommunityPendingImageStoreTests: XCTestCase {
    func testPendingImageIsScopedToOwnerAndChat() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-image-\(UUID().uuidString)", isDirectory: true)
        let store = CommunityPendingImageStore(directory: directory)
        let ownerID = UUID()
        let scopeID = UUID()
        let attachmentID = UUID()
        let data = Data("jpeg".utf8)

        await store.save(
            attachmentID: attachmentID,
            ownerID: ownerID,
            scopeID: scopeID,
            kind: .direct,
            jpegData: data
        )

        let loaded = await store.load(ownerID: ownerID, scopeID: scopeID, kind: .direct)
        XCTAssertEqual(loaded?.attachmentID, attachmentID)
        XCTAssertEqual(loaded?.jpegData, data)
        let otherOwnerImage = await store.load(ownerID: UUID(), scopeID: scopeID, kind: .direct)
        XCTAssertNil(otherOwnerImage)

        await store.remove(ownerID: ownerID, scopeID: scopeID, kind: .direct)
        let removedImage = await store.load(ownerID: ownerID, scopeID: scopeID, kind: .direct)
        XCTAssertNil(removedImage)
    }

    func testPendingImageRejectsOversizedData() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-image-\(UUID().uuidString)", isDirectory: true)
        let store = CommunityPendingImageStore(directory: directory)
        let ownerID = UUID()
        let scopeID = UUID()

        await store.save(
            attachmentID: UUID(),
            ownerID: ownerID,
            scopeID: scopeID,
            kind: .group,
            jpegData: Data(repeating: 1, count: 12_000_001)
        )

        let oversizedImage = await store.load(ownerID: ownerID, scopeID: scopeID, kind: .group)
        XCTAssertNil(oversizedImage)
    }
}
