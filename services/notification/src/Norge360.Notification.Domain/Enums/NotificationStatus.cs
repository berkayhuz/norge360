// <copyright file="NotificationStatus.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Domain.Enums;

public enum NotificationStatus
{
    Pending = 1,
    Queued = 2,
    Processing = 3,
    PartiallyDelivered = 4,
    Delivered = 5,
    Failed = 6,
    DeadLettered = 7
}
