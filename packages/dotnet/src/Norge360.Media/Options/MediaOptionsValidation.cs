// <copyright file="MediaOptionsValidation.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

namespace Norge360.Media.Options;

public sealed class MediaOptionsValidation(IHostEnvironment environment) : IValidateOptions<MediaOptions>
{
    private const string CloudflareR2Provider = "CloudflareR2";
    private const string LocalFileProvider = "LocalFile";
    private const string ProductionCdnHost = "cdn.Norge360.com";
    private static readonly string[] UnsafeMarkers = ["localhost", "127.0.0.1", "example", "local", "dev", "test", "change_me", "replace"];

    public ValidateOptionsResult Validate(string? name, MediaOptions options)
    {
        var failures = new List<string>();
        var isDevelopmentLike = environment.IsDevelopment() ||
            environment.IsEnvironment("Test") ||
            environment.IsEnvironment("Testing");

        ValidateSharedOptions(options, failures, isDevelopmentLike);
        ValidateLocalOptions(options, failures);

        if (isDevelopmentLike)
        {
            ValidateDevelopmentOptions(options, failures);
            return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
        }

        ValidateProductionOptions(options, failures);

        return failures.Count == 0 ? ValidateOptionsResult.Success : ValidateOptionsResult.Fail(failures);
    }

    private static void ValidateSharedOptions(MediaOptions options, List<string> failures, bool allowDevelopmentLoopback)
    {
        if (!Uri.TryCreate(options.PublicBaseUrl, UriKind.Absolute, out var publicBaseUri))
        {
            failures.Add("Media:PublicBaseUrl must be an absolute URL.");
        }
        else if (publicBaseUri.Scheme != Uri.UriSchemeHttps &&
                 !(allowDevelopmentLoopback && publicBaseUri.Scheme == Uri.UriSchemeHttp && publicBaseUri.IsLoopback))
        {
            failures.Add(allowDevelopmentLoopback
                ? "Media:PublicBaseUrl must be an absolute HTTPS URL or a Development HTTP loopback URL."
                : "Media:PublicBaseUrl must be an absolute HTTPS URL.");
        }

        if (options.MaxImageBytes <= 0 || options.MaxImageBytes > 25 * 1024 * 1024)
        {
            failures.Add("Media:MaxImageBytes must be between 1 byte and 25 MB.");
        }

        if (options.MaxImageWidth <= 0 || options.MaxImageWidth > 10000 ||
            options.MaxImageHeight <= 0 || options.MaxImageHeight > 10000)
        {
            failures.Add("Media image dimension limits must be between 1 and 10000 pixels.");
        }

        if (options.AllowedImageContentTypes.Length == 0 || options.AllowedImageExtensions.Length == 0)
        {
            failures.Add("Media allowed image content types/extensions must be configured.");
        }

        if (string.IsNullOrWhiteSpace(options.StorageProvider))
        {
            failures.Add("Media:StorageProvider is required.");
        }
    }

    private static void ValidateLocalOptions(MediaOptions options, List<string> failures)
    {
        if (!string.Equals(options.StorageProvider, LocalFileProvider, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(options.Local.RootPath))
        {
            failures.Add("Media:Local:RootPath is required when LocalFile storage is enabled.");
        }

        if (!IsSafeRequestPath(options.Local.RequestPath))
        {
            failures.Add("Media:Local:RequestPath must be an absolute URL path without traversal.");
        }

        if (Uri.TryCreate(options.PublicBaseUrl, UriKind.Absolute, out var publicBaseUri) &&
            IsSafeRequestPath(options.Local.RequestPath) &&
            !PathsMatch(publicBaseUri.AbsolutePath, options.Local.RequestPath))
        {
            failures.Add("Media:PublicBaseUrl path must match Media:Local:RequestPath when LocalFile storage is enabled.");
        }
    }

    private static void ValidateDevelopmentOptions(MediaOptions options, List<string> failures)
    {
        if (string.Equals(options.StorageProvider, LocalFileProvider, StringComparison.OrdinalIgnoreCase) &&
            Uri.TryCreate(options.PublicBaseUrl, UriKind.Absolute, out var publicBaseUri) &&
            string.Equals(publicBaseUri.Host, ProductionCdnHost, StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Media:PublicBaseUrl must point to the local Development media endpoint when LocalFile storage is enabled.");
        }
    }

    private static void ValidateProductionOptions(MediaOptions options, List<string> failures)
    {
        if (ContainsUnsafeMarker(options.PublicBaseUrl))
        {
            failures.Add("Media:PublicBaseUrl must be a production CDN host.");
        }

        if (!string.Equals(options.StorageProvider, CloudflareR2Provider, StringComparison.OrdinalIgnoreCase))
        {
            failures.Add("Media:StorageProvider must be CloudflareR2 in production.");
        }

        if (string.IsNullOrWhiteSpace(options.CloudflareR2.AccountId) ||
            string.IsNullOrWhiteSpace(options.CloudflareR2.BucketName) ||
            string.IsNullOrWhiteSpace(options.CloudflareR2.AccessKeyId) ||
            string.IsNullOrWhiteSpace(options.CloudflareR2.SecretAccessKey))
        {
            failures.Add("Media:CloudflareR2 AccountId, BucketName, AccessKeyId and SecretAccessKey are required in production.");
        }

        if (ContainsUnsafeMarker(options.CloudflareR2.AccountId) ||
            ContainsUnsafeMarker(options.CloudflareR2.BucketName) ||
            ContainsUnsafeMarker(options.CloudflareR2.AccessKeyId))
        {
            failures.Add("Media:CloudflareR2 configuration contains unsafe placeholder values.");
        }

        if (options.RequireSecurityScannerInProduction &&
            (string.IsNullOrWhiteSpace(options.SecurityScannerProvider) ||
             string.Equals(options.SecurityScannerProvider, "Noop", StringComparison.OrdinalIgnoreCase)))
        {
            failures.Add("Media:SecurityScannerProvider must be a production scanner when RequireSecurityScannerInProduction is enabled.");
        }
    }

    private static bool IsSafeRequestPath(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            !value.StartsWith("/", StringComparison.Ordinal) ||
            value.Contains("\\", StringComparison.Ordinal) ||
            value.Contains("..", StringComparison.Ordinal) ||
            value.Contains("?", StringComparison.Ordinal) ||
            value.Contains("#", StringComparison.Ordinal))
        {
            return false;
        }

        return true;
    }

    private static bool PathsMatch(string publicBasePath, string requestPath)
    {
        static string Normalize(string path) => string.IsNullOrWhiteSpace(path.Trim('/'))
            ? "/"
            : $"/{path.Trim('/')}";

        return string.Equals(Normalize(publicBasePath), Normalize(requestPath), StringComparison.OrdinalIgnoreCase);
    }

    private static bool ContainsUnsafeMarker(string value) =>
        UnsafeMarkers.Any(marker => value.Contains(marker, StringComparison.OrdinalIgnoreCase));
}
