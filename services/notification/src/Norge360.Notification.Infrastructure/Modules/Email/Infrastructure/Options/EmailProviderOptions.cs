// <copyright file="EmailProviderOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Infrastructure.Modules.Email.Infrastructure.Options;

public sealed class EmailProviderOptions
{
    public const string SectionName = "Notification:Email";

    [Required]
    public string Provider { get; init; } = "ses";

    public string[] ApprovedSenderDomains { get; init; } = ["norge360.com"];
}
