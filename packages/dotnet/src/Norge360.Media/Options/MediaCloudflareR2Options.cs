// <copyright file="MediaCloudflareR2Options.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Media.Options;

public sealed class MediaCloudflareR2Options
{
    public string AccountId { get; init; } = string.Empty;
    public string BucketName { get; init; } = string.Empty;
    public string AccessKeyId { get; init; } = string.Empty;
    public string SecretAccessKey { get; init; } = string.Empty;
    public string EndpointUrl { get; init; } = string.Empty;
    public string ObjectKeyPrefix { get; init; } = "Norge360";
    public bool UsePathStyle { get; init; } = true;
}
