// <copyright file="MediaStorageDependencyInjection.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Norge360.Media.Abstractions;
using Norge360.Media.Options;
using Norge360.Media.Security;
using Norge360.Media.Services;
using Norge360.Media.Urls;
using Norge360.Media.Validation;

namespace Norge360.Media.Storage;

public static class MediaServiceCollectionExtensions
{
    public static IServiceCollection AddNorge360Media(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        _ = environment;
        services
            .AddOptions<MediaOptions>()
            .Bind(configuration.GetSection(MediaOptions.SectionName))
            .ValidateOnStart();
        services.AddSingleton<IValidateOptions<MediaOptions>, MediaOptionsValidation>();

        services.AddSingleton<IMediaUrlBuilder, MediaUrlBuilder>();
        services.AddScoped<IImageValidator, DefaultImageValidator>();
        services.AddScoped<IImageMetadataReader, DefaultImageMetadataReader>();
        services.AddScoped<IMediaSecurityScanner, NoopMediaSecurityScanner>();
        services.AddScoped<IMediaAssetService, MediaAssetService>();

        var provider = configuration.GetSection(MediaOptions.SectionName).Get<MediaOptions>()?.StorageProvider ?? "LocalFile";
        if (string.Equals(provider, "CloudflareR2", StringComparison.OrdinalIgnoreCase))
        {
            services.AddScoped<IMediaStorageProvider, CloudflareR2MediaStorageProvider>();
        }
        else
        {
            services.AddScoped<IMediaStorageProvider, LocalFileMediaStorageProvider>();
        }

        return services;
    }
}

public sealed class LocalFileMediaStorageProvider(IOptions<MediaOptions> options) : IMediaStorageProvider
{
    public string Name => "LocalFile";

    public async Task SaveAsync(string key, Stream content, string contentType, CancellationToken cancellationToken)
    {
        var fullPath = ResolvePath(key);
        var directory = Path.GetDirectoryName(fullPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using var file = File.Create(fullPath);
        await content.CopyToAsync(file, cancellationToken);
    }

    public Task DeleteAsync(string key, CancellationToken cancellationToken)
    {
        var fullPath = ResolvePath(key);
        if (File.Exists(fullPath))
        {
            File.Delete(fullPath);
        }

        return Task.CompletedTask;
    }

    public Task<bool> ExistsAsync(string key, CancellationToken cancellationToken)
        => Task.FromResult(File.Exists(ResolvePath(key)));

    private string ResolvePath(string key)
    {
        var root = Path.GetFullPath(options.Value.Local.RootPath);
        var safeKey = key.Replace('\\', '/').TrimStart('/');
        if (safeKey.Contains("..", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Invalid storage key.");
        }

        var fullPath = Path.GetFullPath(Path.Combine(root, safeKey.Replace('/', Path.DirectorySeparatorChar)));
        if (!fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Invalid storage key path.");
        }

        return fullPath;
    }
}

public sealed class CloudflareR2MediaStorageProvider : IMediaStorageProvider
{
    private readonly AmazonS3Client _s3;
    private readonly MediaOptions _options;

    public CloudflareR2MediaStorageProvider(IOptions<MediaOptions> options)
    {
        _options = options.Value;
        var creds = new BasicAWSCredentials(_options.CloudflareR2.AccessKeyId, _options.CloudflareR2.SecretAccessKey);
        var endpoint = !string.IsNullOrWhiteSpace(_options.CloudflareR2.EndpointUrl)
            ? _options.CloudflareR2.EndpointUrl
            : $"https://{_options.CloudflareR2.AccountId}.r2.cloudflarestorage.com";
        var config = new AmazonS3Config
        {
            ServiceURL = endpoint,
            ForcePathStyle = _options.CloudflareR2.UsePathStyle
        };

        _s3 = new AmazonS3Client(creds, config);
    }

    public string Name => "CloudflareR2";

    public async Task SaveAsync(string key, Stream content, string contentType, CancellationToken cancellationToken)
    {
        await _s3.PutObjectAsync(new PutObjectRequest
        {
            BucketName = _options.CloudflareR2.BucketName,
            Key = key,
            InputStream = content,
            ContentType = contentType
        }, cancellationToken);
    }

    public async Task DeleteAsync(string key, CancellationToken cancellationToken)
    {
        await _s3.DeleteObjectAsync(new DeleteObjectRequest
        {
            BucketName = _options.CloudflareR2.BucketName,
            Key = key
        }, cancellationToken);
    }

    public async Task<bool> ExistsAsync(string key, CancellationToken cancellationToken)
    {
        try
        {
            await _s3.GetObjectMetadataAsync(new GetObjectMetadataRequest
            {
                BucketName = _options.CloudflareR2.BucketName,
                Key = key
            }, cancellationToken);
            return true;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return false;
        }
    }
}
