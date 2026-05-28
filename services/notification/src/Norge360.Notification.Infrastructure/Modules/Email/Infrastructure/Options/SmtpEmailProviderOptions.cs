// <copyright file="SmtpEmailProviderOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;

public sealed class SmtpEmailProviderOptions
{
    public const string SectionName = "Notification:Email:Smtp";

    [Required]
    public string Host { get; init; } = string.Empty;

    [Range(1, 65535)]
    public int Port { get; init; } = 587;

    [Required]
    [EmailAddress]
    public string FromAddress { get; init; } = "notifications@norge360.com";

    [Required]
    public string FromName { get; init; } = "Norge360 Notifications";

    public string? UserName { get; init; }
    public string? Password { get; init; }
    public bool UseStartTls { get; init; } = true;
}
