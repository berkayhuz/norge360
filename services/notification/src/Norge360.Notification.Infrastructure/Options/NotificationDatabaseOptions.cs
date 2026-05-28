// <copyright file="NotificationDatabaseOptions.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Infrastructure.Options;

public sealed class NotificationDatabaseOptions
{
    public const string SectionName = "Notification:Database";

    public bool ApplyMigrationsOnStartup { get; init; }
}
