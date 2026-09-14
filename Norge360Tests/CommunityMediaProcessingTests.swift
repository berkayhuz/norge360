import ImageIO
import UIKit
import XCTest

@testable import Norge360

final class CommunityMediaProcessingTests: XCTestCase {
    func testNetworkImageDecoderRejectsOversizedPayloadBeforeDecoding() {
        let oversizedData = Data(
            repeating: 0,
            count: CommunityImageNetworkLoader.maximumDownloadedBytes + 1
        )

        XCTAssertNil(CommunityImageDecoding.image(from: oversizedData))
    }

    func testNetworkImageDecoderDownsamplesFullImageToSafeDimension() throws {
        let input = try makePNG(size: CGSize(width: 5_000, height: 4_000))

        let image = try XCTUnwrap(CommunityImageDecoding.image(from: input))

        XCTAssertLessThanOrEqual(max(image.cgImage?.width ?? 0, image.cgImage?.height ?? 0), 4_096)
    }

    func testPrepareJPEGDownsamplesLargeInputAndBoundsOutput() async throws {
        let input = try makePNG(size: CGSize(width: 3_200, height: 2_400))

        let upload = try await CommunityImageProcessing.prepareJPEG(from: input)

        XCTAssertLessThanOrEqual(max(upload.width, upload.height), 2_048)
        XCTAssertLessThanOrEqual(upload.data.count, 3_000_000)
        let uploadDimensions = try imageDimensions(upload.data)
        XCTAssertEqual(uploadDimensions.width, upload.width)
        XCTAssertEqual(uploadDimensions.height, upload.height)
    }

    func testPreviewAndCropExportRemainBounded() async throws {
        let input = try makePNG(size: CGSize(width: 2_400, height: 1_800))

        let preview = try await CommunityImageProcessing.previewJPEG(from: input)
        let previewSize = try imageDimensions(preview)
        let outputSize = CGSize(width: 480, height: 360)
        let crop = try await CommunityImageProcessing.cropJPEG(
            from: preview,
            cropRect: CGRect(x: 0, y: 0, width: previewSize.0 / 2, height: previewSize.1 / 2),
            outputSize: outputSize
        )

        let cropDimensions = try imageDimensions(crop)
        XCTAssertEqual(cropDimensions.width, 480)
        XCTAssertEqual(cropDimensions.height, 360)
        XCTAssertLessThanOrEqual(crop.count, 3_000_000)
    }

    func testRotatePreviewSwapsDimensions() async throws {
        let input = try makePNG(size: CGSize(width: 1_200, height: 800))
        let preview = try await CommunityImageProcessing.previewJPEG(from: input)
        let previewSize = try imageDimensions(preview)

        let rotated = try await CommunityImageProcessing.rotateJPEG(from: preview)
        let rotatedSize = try imageDimensions(rotated)

        XCTAssertEqual(rotatedSize.width, previewSize.height)
        XCTAssertEqual(rotatedSize.height, previewSize.width)
    }

    private func makePNG(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemYellow.setFill()
            context.fill(
                CGRect(x: size.width * 0.25, y: size.height * 0.25, width: size.width * 0.5, height: size.height * 0.5))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func imageDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue)
        let height = try XCTUnwrap((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue)
        return (width, height)
    }
}
