import CoreGraphics
import XCTest

@testable import Norge360

final class CommunityCropGeometryTests: XCTestCase {
    func testPortraitPhotoKeepsCentralSquareWithoutStretching() {
        let image = CGSize(width: 800, height: 1_200)
        let viewport = CGSize(width: 300, height: 300)
        let rect = CommunityCropGeometry.imageRect(image: image, viewport: viewport, zoom: 1, offset: .zero)

        assertRect(rect, equals: CGRect(x: 0, y: -75, width: 300, height: 450))
        assertRect(
            visibleSourceRect(image: image, viewport: viewport, rect: rect),
            equals: CGRect(x: 0, y: 200, width: 800, height: 800))
    }

    func testLandscapePhotoKeepsCentralSquareWithoutStretching() {
        let image = CGSize(width: 1_600, height: 900)
        let viewport = CGSize(width: 300, height: 300)
        let rect = CommunityCropGeometry.imageRect(image: image, viewport: viewport, zoom: 1, offset: .zero)

        XCTAssertEqual(rect.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(rect.width / rect.height, image.width / image.height, accuracy: 0.0001)
        assertRect(
            visibleSourceRect(image: image, viewport: viewport, rect: rect),
            equals: CGRect(x: 350, y: 0, width: 900, height: 900))
    }

    func testCoverCropPreservesRequestedAspectAndImageCenter() {
        let image = CGSize(width: 800, height: 1_200)
        let viewport = CGSize(width: 360, height: 180)
        let rect = CommunityCropGeometry.imageRect(image: image, viewport: viewport, zoom: 1, offset: .zero)

        assertRect(
            visibleSourceRect(image: image, viewport: viewport, rect: rect),
            equals: CGRect(x: 0, y: 400, width: 800, height: 400))
    }

    func testExtremeOffsetsNeverRevealEmptyPixels() {
        let viewport = CGSize(width: 360, height: 240)
        for image in [CGSize(width: 400, height: 1_600), CGSize(width: 1_600, height: 400)] {
            for zoom in [CGFloat(1), 2, 4] {
                for offset in [CGSize(width: -100_000, height: -100_000), CGSize(width: 100_000, height: 100_000)] {
                    let rect = CommunityCropGeometry.imageRect(
                        image: image, viewport: viewport, zoom: zoom, offset: offset)
                    XCTAssertLessThanOrEqual(rect.minX, 0.0001)
                    XCTAssertLessThanOrEqual(rect.minY, 0.0001)
                    XCTAssertGreaterThanOrEqual(rect.maxX, viewport.width - 0.0001)
                    XCTAssertGreaterThanOrEqual(rect.maxY, viewport.height - 0.0001)
                    let crop = visibleSourceRect(image: image, viewport: viewport, rect: rect)
                    XCTAssertGreaterThanOrEqual(crop.minX, -0.0001)
                    XCTAssertGreaterThanOrEqual(crop.minY, -0.0001)
                    XCTAssertLessThanOrEqual(crop.maxX, image.width + 0.0001)
                    XCTAssertLessThanOrEqual(crop.maxY, image.height + 0.0001)
                }
            }
        }
    }

    func testZoomAndDragSelectTheSameSourceAreaUsedForExport() {
        let image = CGSize(width: 1_000, height: 1_000)
        let viewport = CGSize(width: 250, height: 250)
        let rect = CommunityCropGeometry.imageRect(
            image: image, viewport: viewport, zoom: 2, offset: CGSize(width: 50, height: -25)
        )

        assertRect(rect, equals: CGRect(x: -75, y: -150, width: 500, height: 500))
        assertRect(
            visibleSourceRect(image: image, viewport: viewport, rect: rect),
            equals: CGRect(x: 150, y: 300, width: 500, height: 500))
    }

    func testZoomBelowOneStillFillsViewport() {
        let image = CGSize(width: 800, height: 1_200)
        let viewport = CGSize(width: 300, height: 300)
        for zoom in [CGFloat(-2), 0, 0.5] {
            assertRect(
                CommunityCropGeometry.imageRect(image: image, viewport: viewport, zoom: zoom, offset: .zero),
                equals: CGRect(x: 0, y: -75, width: 300, height: 450))
        }
    }

    func testMissingImageOrViewportDoesNotProduceInvalidGeometry() {
        for (image, viewport) in [
            (CGSize.zero, CGSize(width: 300, height: 300)),
            (CGSize(width: 800, height: 1_200), CGSize.zero),
            (CGSize(width: -800, height: 1_200), CGSize(width: 300, height: 300)),
        ] {
            XCTAssertEqual(
                CommunityCropGeometry.imageRect(image: image, viewport: viewport, zoom: 1, offset: .zero), .zero)
        }
    }

    // Invert the preview transform to verify the source pixels approved for export.
    private func visibleSourceRect(image: CGSize, viewport: CGSize, rect: CGRect) -> CGRect {
        let scale = image.width / rect.width
        return CGRect(
            x: -rect.minX * scale, y: -rect.minY * scale,
            width: viewport.width * scale, height: viewport.height * scale)
    }

    private func assertRect(
        _ actual: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }
}
