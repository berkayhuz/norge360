// <copyright file="INotificationQueue.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Application.Abstractions;

public interface INotificationQueue
{
    Task EnqueueAsync(
        NotificationMessage message,
        CancellationToken cancellationToken = default);

    Task<NotificationMessage?> DequeueAsync(CancellationToken cancellationToken);

    Task CompleteAsync(
        NotificationMessage message,
        CancellationToken cancellationToken = default);

    Task AbandonAsync(
        NotificationMessage message,
        bool requeue,
        CancellationToken cancellationToken = default);
}
