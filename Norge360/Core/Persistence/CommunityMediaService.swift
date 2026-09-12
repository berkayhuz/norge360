import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum CommunityMediaError: LocalizedError {
    case unsupportedImage
    case tooManyImages

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: AppStrings.localized("media.unsupported_image")
        case .tooManyImages: AppStrings.localized("media.too_many_images")
        }
    }
}

enum CommunityImageProcessing {
    private static let maximumPixelDimension = 2_048
    private static let maximumDataBytes = 3_000_000
    private static let maximumInputBytes = 50_000_000
    private static let maximumSourcePixelDimension: Int64 = 12_000
    private static let maximumSourcePixelCount: Int64 = 64_000_000

    static func prepareCameraJPEG(from image: UIImage) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                guard let data = image.jpegData(compressionQuality: 0.82), data.count <= maximumInputBytes else {
                    throw CommunityMediaError.unsupportedImage
                }
                return data
            }
        }.value
    }

    static func prepareJPEG(from data: Data) async throws -> CommunityImageUpload {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let image = try downsampledImage(from: data, maxPixelDimension: maximumPixelDimension)
                let jpegData = try compressedJPEG(from: image, initialQuality: 0.82)
                return CommunityImageUpload(
                    data: jpegData,
                    width: image.width,
                    height: image.height
                )
            }
        }.value
    }

    static func previewJPEG(from data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let image = try downsampledImage(from: data, maxPixelDimension: maximumPixelDimension)
                return try compressedJPEG(from: image, initialQuality: 0.9)
            }
        }.value
    }

    static func cropJPEG(from data: Data, cropRect: CGRect, outputSize: CGSize) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let image = try downsampledImage(from: data, maxPixelDimension: maximumPixelDimension)
                let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                let clippedCrop = cropRect.intersection(bounds).integral
                guard !clippedCrop.isNull, clippedCrop.width > 0, clippedCrop.height > 0 else {
                    throw CommunityMediaError.unsupportedImage
                }
                guard let croppedImage = image.cropping(to: clippedCrop) else {
                    throw CommunityMediaError.unsupportedImage
                }
                let outputWidth = max(1, min(maximumPixelDimension, Int(outputSize.width.rounded())))
                let outputHeight = max(1, min(maximumPixelDimension, Int(outputSize.height.rounded())))
                let renderedImage = try resizedImage(croppedImage, width: outputWidth, height: outputHeight)
                return try compressedJPEG(from: renderedImage, initialQuality: 0.9)
            }
        }.value
    }

    static func rotateJPEG(from data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let image = try downsampledImage(from: data, maxPixelDimension: maximumPixelDimension)
                let rotatedImage = try rotatedImage(image)
                return try compressedJPEG(from: rotatedImage, initialQuality: 0.9)
            }
        }.value
    }

    private static func downsampledImage(from data: Data, maxPixelDimension: Int) throws -> CGImage {
        guard data.count <= maximumInputBytes else { throw CommunityMediaError.unsupportedImage }
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
            width > 0,
            height > 0,
            width <= maximumSourcePixelDimension,
            height <= maximumSourcePixelDimension,
            width * height <= maximumSourcePixelCount
        else {
            throw CommunityMediaError.unsupportedImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw CommunityMediaError.unsupportedImage
        }
        return image
    }

    private static func resizedImage(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw CommunityMediaError.unsupportedImage
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let renderedImage = context.makeImage() else { throw CommunityMediaError.unsupportedImage }
        return renderedImage
    }

    private static func rotatedImage(_ image: CGImage) throws -> CGImage {
        let width = image.height
        let height = image.width
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw CommunityMediaError.unsupportedImage
        }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rotatedImage = context.makeImage() else { throw CommunityMediaError.unsupportedImage }
        return rotatedImage
    }

    private static func compressedJPEG(from image: CGImage, initialQuality: CGFloat) throws -> Data {
        var compression = initialQuality
        var compressedData = try jpegData(from: image, quality: compression)
        while compressedData.count > maximumDataBytes, compression > 0.45 {
            compression -= 0.1
            compressedData = try jpegData(from: image, quality: compression)
        }
        guard compressedData.count <= maximumDataBytes else { throw CommunityMediaError.unsupportedImage }
        return compressedData
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            throw CommunityMediaError.unsupportedImage
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CommunityMediaError.unsupportedImage }
        return data as Data
    }
}
