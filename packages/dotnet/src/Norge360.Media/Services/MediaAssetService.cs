// <copyright file="MediaAssetService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Media;
using Norge360.Media.Abstractions;
using Norge360.Media.Models;
using Norge360.Media.Options;
using Norge360.Media.Security;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.Formats.Webp;

namespace Norge360.Media.Services;

public sealed class MediaAssetService(
    IMediaStorageProvider storageProvider,
    IMediaUrlBuilder urlBuilder,
    IImageValidator imageValidator,
    IMediaSecurityScanner securityScanner,
    IOptions<MediaOptions> options) : IMediaAssetService
{
    public async Task<MediaUploadResult> UploadImageAsync(MediaUploadRequest request, CancellationToken cancellationToken)
    {
        var validation = await imageValidator.ValidateAsync(request.OriginalFileName, request.ContentType, request.Content, request.Length, cancellationToken);
        if (!validation.IsValid || string.IsNullOrWhiteSpace(validation.CanonicalContentType) || string.IsNullOrWhiteSpace(validation.Extension))
        {
            throw new MediaValidationException(validation.FailureReason ?? "Image validation failed.");
        }

        var tenantSegment = SanitizePathSegment(request.TenantId);
        var purposeSegment = SanitizePathSegment(request.Purpose);
        var assetId = Guid.NewGuid();
        var keyPrefix = string.IsNullOrWhiteSpace(options.Value.CloudflareR2.ObjectKeyPrefix)
            ? string.Empty
            : $"{SanitizePathSegment(options.Value.CloudflareR2.ObjectKeyPrefix)}/";
        var objectKey = $"{keyPrefix}media/{tenantSegment}/{purposeSegment}/{DateTime.UtcNow:yyyy}/{DateTime.UtcNow:MM}/{assetId}/original{validation.Extension}";

        using var imageCopy = new MemoryStream();
        await request.Content.CopyToAsync(imageCopy, cancellationToken);
        imageCopy.Position = 0;

        var scan = await securityScanner.ScanAsync(
            new MediaSecurityScanRequest(
                request.OriginalFileName,
                validation.CanonicalContentType,
                imageCopy,
                imageCopy.Length,
                request.TenantId,
                request.Purpose,
                request.Module),
            cancellationToken);
        imageCopy.Position = 0;

        if (!scan.IsSafe)
        {
            throw new MediaValidationException(scan.FailureReason ?? "Image security scan failed.");
        }

        var sanitizedImage = await DecodeAndSanitizeAsync(imageCopy, validation.CanonicalContentType, cancellationToken);

        if (sanitizedImage.Width > options.Value.MaxImageWidth || sanitizedImage.Height > options.Value.MaxImageHeight)
        {
            throw new MediaValidationException("Image dimensions exceed the configured limit.");
        }

        sanitizedImage.Content.Position = 0;
        var hash = await MediaHashing.ComputeSha256HexAsync(sanitizedImage.Content, cancellationToken);
        sanitizedImage.Content.Position = 0;

        await storageProvider.SaveAsync(objectKey, sanitizedImage.Content, validation.CanonicalContentType, cancellationToken);

        return new MediaUploadResult(
            validation.CanonicalContentType,
            validation.Extension,
            sanitizedImage.Content.Length,
            hash,
            sanitizedImage.Width,
            sanitizedImage.Height,
            storageProvider.Name,
            objectKey,
            urlBuilder.BuildPublicUrl(objectKey));
    }

    public Task DeleteAsync(string storageKey, CancellationToken cancellationToken)
        => storageProvider.DeleteAsync(storageKey, cancellationToken);

    private static async Task<SanitizedImage> DecodeAndSanitizeAsync(Stream content, string contentType, CancellationToken cancellationToken)
    {
        try
        {
            using var image = await Image.LoadAsync(content, cancellationToken);
            var width = image.Width;
            var height = image.Height;
            image.Metadata.ExifProfile = null;
            image.Metadata.IccProfile = null;
            image.Metadata.XmpProfile = null;

            var output = new MemoryStream();
            if (string.Equals(contentType, "image/png", StringComparison.OrdinalIgnoreCase))
            {
                await image.SaveAsync(output, new PngEncoder(), cancellationToken);
            }
            else if (string.Equals(contentType, "image/jpeg", StringComparison.OrdinalIgnoreCase))
            {
                await image.SaveAsync(output, new JpegEncoder { Quality = 90 }, cancellationToken);
            }
            else if (string.Equals(contentType, "image/webp", StringComparison.OrdinalIgnoreCase))
            {
                await image.SaveAsync(output, new WebpEncoder(), cancellationToken);
            }
            else
            {
                throw new MediaValidationException("Unsupported image content type.");
            }

            output.Position = 0;
            return new SanitizedImage(output, width, height);
        }
        catch (UnknownImageFormatException ex)
        {
            throw new MediaValidationException("Image payload could not be decoded.", ex);
        }
        catch (InvalidImageContentException ex)
        {
            throw new MediaValidationException("Image payload is corrupt.", ex);
        }
    }

    private static string SanitizePathSegment(string value)
    {
        var safe = value.Trim().Replace('\\', '-').Replace('/', '-').Replace("..", "-", StringComparison.Ordinal);
        return string.IsNullOrWhiteSpace(safe) ? "unknown" : safe.ToLowerInvariant();
    }

    private sealed record SanitizedImage(MemoryStream Content, int Width, int Height);
}
