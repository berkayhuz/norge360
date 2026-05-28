// <copyright file="NotificationDeliveryStatus.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

namespace Norge360.Notification.Domain.Enums;

public enum NotificationDeliveryStatus
{
    Pending = 1,
    Succeeded = 2,
    Failed = 3,
    Skipped = 4
}
