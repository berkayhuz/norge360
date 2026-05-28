// <copyright file="NotificationDispatchOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Application.Options;

public sealed class NotificationDispatchOptions
{
    public const string SectionName = "Notification:Dispatch";

    [Range(1, 10)]
    public int MaxAttempts { get; init; } = 3;

    [Range(0, 300)]
    public int RetryDelayMilliseconds { get; init; } = 250;

    [Range(0, 86_400)]
    public int MaxRetryDelaySeconds { get; init; } = 30;
}
