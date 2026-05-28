// <copyright file="INotificationDeliveryLog.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Models;
using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Application.Abstractions;

public interface INotificationDeliveryLog
{
    Task<NotificationMessage> CreateNotificationAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken);

    Task<NotificationMessage?> GetNotificationAsync(
        Guid notificationId,
        CancellationToken cancellationToken);

    Task<IReadOnlySet<NotificationChannel>> GetSucceededChannelsAsync(
        Guid notificationId,
        CancellationToken cancellationToken);

    Task MarkQueuedAsync(
        Guid notificationId,
        CancellationToken cancellationToken);

    Task MarkProcessingAsync(
        Guid notificationId,
        CancellationToken cancellationToken);

    Task MarkDeadLetteredAsync(
        Guid notificationId,
        string reason,
        CancellationToken cancellationToken);

    Task RecordAttemptAsync(
        Guid notificationId,
        NotificationChannelResult result,
        string? recipient,
        CancellationToken cancellationToken);
}
