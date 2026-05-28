// <copyright file="NotificationWorkerOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.ComponentModel.DataAnnotations;

namespace Norge360.Notification.Worker;

public sealed class NotificationWorkerOptions
{
    public const string SectionName = "Notification:Worker";

    [Range(1, 64)]
    public int MaxConcurrentMessages { get; init; } = 4;

    [Range(100, 60_000)]
    public int EmptyQueueDelayMilliseconds { get; init; } = 500;

    public bool DeadLetterUnexpectedFailures { get; init; } = true;
}
