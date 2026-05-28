// <copyright file="SendNotificationResponse.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Models;

namespace Norge360.Notification.Contracts.Notifications.Responses;

public sealed record SendNotificationResponse(
    Guid NotificationId,
    bool Accepted,
    IReadOnlyCollection<NotificationChannelResult> ChannelResults);
