// <copyright file="EfNotificationDeliveryLog.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Models;
using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Domain.Entities;
using Norge360.Notification.Domain.Enums;

namespace Norge360.Notification.Infrastructure.Persistence;

public sealed class EfNotificationDeliveryLog(NotificationDbContext dbContext) : INotificationDeliveryLog
{
    public async Task<NotificationMessage> CreateNotificationAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.IdempotencyKey))
        {
            var existing = await dbContext.Notifications
                .Where(x => x.IdempotencyKey == request.IdempotencyKey)
                .FirstOrDefaultAsync(cancellationToken);

            if (existing is not null)
            {
                return existing;
            }
        }

        var notification = new NotificationMessage(
            Guid.NewGuid(),
            request.Recipient.UserId,
            request.Category,
            request.Priority,
            request.Subject.Trim(),
            request.TextBody,
            request.HtmlBody,
            request.TemplateKey,
            JsonSerializer.Serialize(request.Channels.Distinct()),
            request.Recipient.EmailAddress,
            request.Recipient.PhoneNumber,
            request.Recipient.PushToken,
            request.Recipient.DisplayName,
            JsonSerializer.Serialize(request.Metadata),
            request.CorrelationId,
            request.IdempotencyKey,
            DateTime.UtcNow);

        await dbContext.Notifications.AddAsync(notification, cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);
        return notification;
    }

    public Task<NotificationMessage?> GetNotificationAsync(
        Guid notificationId,
        CancellationToken cancellationToken) =>
        dbContext.Notifications.FirstOrDefaultAsync(x => x.Id == notificationId, cancellationToken);

    public async Task<IReadOnlySet<NotificationChannel>> GetSucceededChannelsAsync(
        Guid notificationId,
        CancellationToken cancellationToken)
    {
        var channels = await dbContext.DeliveryAttempts
            .Where(x => x.NotificationMessageId == notificationId && x.Status == NotificationDeliveryStatus.Succeeded)
            .Select(x => x.Channel)
            .Distinct()
            .ToListAsync(cancellationToken);

        return channels.ToHashSet();
    }

    public async Task MarkQueuedAsync(Guid notificationId, CancellationToken cancellationToken)
    {
        var notification = await dbContext.Notifications.FirstAsync(x => x.Id == notificationId, cancellationToken);
        notification.MarkQueued(DateTime.UtcNow);
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    public async Task MarkProcessingAsync(Guid notificationId, CancellationToken cancellationToken)
    {
        var notification = await dbContext.Notifications.FirstAsync(x => x.Id == notificationId, cancellationToken);
        notification.MarkProcessing(DateTime.UtcNow);
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    public async Task MarkDeadLetteredAsync(Guid notificationId, string reason, CancellationToken cancellationToken)
    {
        var notification = await dbContext.Notifications
            .Include(x => x.DeliveryAttempts)
            .FirstAsync(x => x.Id == notificationId, cancellationToken);
        notification.AddDeliveryAttempt(new NotificationDeliveryAttempt(
            Guid.NewGuid(),
            notificationId,
            NotificationChannel.InApp,
            NotificationDeliveryStatus.Failed,
            "notification-worker",
            notification.UserId?.ToString("D"),
            null,
            "dead_lettered",
            reason,
            0,
            DateTime.UtcNow));
        notification.MarkDeadLettered(DateTime.UtcNow);
        await dbContext.SaveChangesAsync(cancellationToken);
    }

    public async Task RecordAttemptAsync(
        Guid notificationId,
        NotificationChannelResult result,
        string? recipient,
        CancellationToken cancellationToken)
    {
        var notification = await dbContext.Notifications
            .Include(x => x.DeliveryAttempts)
            .FirstAsync(x => x.Id == notificationId, cancellationToken);

        var attempt = new NotificationDeliveryAttempt(
            Guid.NewGuid(),
            notificationId,
            result.Channel,
            result.Succeeded ? NotificationDeliveryStatus.Succeeded : NotificationDeliveryStatus.Failed,
            result.Provider ?? "unregistered",
            recipient,
            result.ExternalMessageId,
            result.ErrorCode,
            result.ErrorMessage,
            result.AttemptCount,
            DateTime.UtcNow);

        notification.AddDeliveryAttempt(attempt);
        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
