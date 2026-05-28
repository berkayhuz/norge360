// <copyright file="NotificationChannelResult.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Enums;

namespace Norge360.Notification.Contracts.Notifications.Models;

public sealed record NotificationChannelResult(
    NotificationChannel Channel,
    bool Succeeded,
    string? Provider,
    string? ExternalMessageId,
    string? ErrorCode,
    string? ErrorMessage,
    int AttemptCount);
