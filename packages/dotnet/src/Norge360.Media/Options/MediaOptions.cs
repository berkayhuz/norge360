// <copyright file="MediaOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Media.Options;

public sealed class MediaOptions
{
    public const string SectionName = "Media";

    public string PublicBaseUrl { get; init; } = "https://cdn.Norge360.com";
    public string StorageProvider { get; init; } = "LocalFile";
    public long MaxImageBytes { get; init; } = 10 * 1024 * 1024;
    public int MaxImageWidth { get; init; } = 4096;
    public int MaxImageHeight { get; init; } = 4096;
    public string SecurityScannerProvider { get; init; } = "Noop";
    public bool RequireSecurityScannerInProduction { get; init; } = true;
    public string[] AllowedImageContentTypes { get; init; } = ["image/jpeg", "image/png", "image/webp"];
    public string[] AllowedImageExtensions { get; init; } = [".jpg", ".jpeg", ".png", ".webp"];
    public MediaLocalOptions Local { get; init; } = new();
    public MediaCloudflareR2Options CloudflareR2 { get; init; } = new();
}
