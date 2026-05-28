// <copyright file="DefaultImageValidator.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Media.Abstractions;
using Norge360.Media.Models;
using Norge360.Media.Options;

namespace Norge360.Media.Validation;

public sealed class DefaultImageValidator(IOptions<MediaOptions> optionsAccessor) : IImageValidator
{
    private readonly MediaOptions options = optionsAccessor.Value;

    public async Task<ImageValidationResult> ValidateAsync(string fileName, string declaredContentType, Stream content, long length, CancellationToken cancellationToken)
    {
        if (length <= 0 || length > options.MaxImageBytes)
        {
            return new(false, "File size is invalid.", null, null);
        }

        var extension = Path.GetExtension(fileName)?.ToLowerInvariant() ?? string.Empty;
        if (!options.AllowedImageExtensions.Contains(extension, StringComparer.OrdinalIgnoreCase))
        {
            return new(false, "File extension is not allowed.", null, null);
        }

        var header = new byte[32];
        var read = await content.ReadAsync(header.AsMemory(0, header.Length), cancellationToken);
        content.Position = 0;
        if (read < 12)
        {
            return new(false, "File payload is too short.", null, null);
        }

        if (IsJpeg(header, read))
        {
            return EnsureDeclaredContentType(declaredContentType, "image/jpeg", extension);
        }

        if (IsPng(header, read))
        {
            return EnsureDeclaredContentType(declaredContentType, "image/png", extension);
        }

        if (IsWebp(header, read))
        {
            return EnsureDeclaredContentType(declaredContentType, "image/webp", extension);
        }

        return new(false, "Unsupported or invalid image type.", null, null);
    }

    private static ImageValidationResult EnsureDeclaredContentType(string declaredContentType, string canonicalContentType, string extension)
    {
        if (!string.IsNullOrWhiteSpace(declaredContentType) &&
            !string.Equals(declaredContentType, canonicalContentType, StringComparison.OrdinalIgnoreCase))
        {
            return new(false, "Declared content type does not match file content.", null, null);
        }

        return new(true, null, canonicalContentType, extension);
    }

    private static bool IsJpeg(byte[] header, int read) =>
        read >= 3 && header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF;

    private static bool IsPng(byte[] header, int read) =>
        read >= 8 &&
        header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 &&
        header[4] == 0x0D && header[5] == 0x0A && header[6] == 0x1A && header[7] == 0x0A;

    private static bool IsWebp(byte[] header, int read) =>
        read >= 12 &&
        header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46 &&
        header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50;
}
