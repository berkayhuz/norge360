// <copyright file="INotificationProcessor.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Application.Abstractions;

public interface INotificationProcessor
{
    Task ProcessAsync(
        NotificationMessage message,
        CancellationToken cancellationToken = default);
}
