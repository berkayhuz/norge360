// <copyright file="AmazonSesEmailProviderOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;

public sealed class AmazonSesEmailProviderOptions
{
    public const string SectionName = "Notification:Email:AmazonSes";

    [Required]
    public string Region { get; init; } = "eu-central-1";

    [Required]
    [EmailAddress]
    public string FromAddress { get; init; } = "notifications@norge360.com";

    [Required]
    public string FromName { get; init; } = "Norge360 Notifications";

    public string? AccessKeyId { get; init; }
    public string? SecretAccessKey { get; init; }
    public string? EndpointUrl { get; init; }
    public string? ConfigurationSetName { get; init; }
}
