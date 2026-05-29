// <copyright file="InAppNotificationChannelSender.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Infrastructure.Persistence;

namespace Norge360.Notification.Infrastructure.Channels;

public sealed class InAppNotificationChannelSender(NotificationDbContext dbContext) : INotificationChannelSender
{
    public NotificationChannel Channel => NotificationChannel.InApp;
    public string ProviderName => "notification-db";

    public async Task<NotificationChannelSendResult> SendAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Recipient.UserId is null)
        {
            return new NotificationChannelSendResult(
                Succeeded: false,
                ExternalMessageId: null,
                ErrorCode: "in_app_recipient_missing",
                ErrorMessage: "In-App channel requires recipient user id.");
        }

        var record = new InAppNotificationRecord(
            Guid.NewGuid(),
            request.Recipient.UserId.Value,
            request.Subject,
            request.TextBody,
            request.CorrelationId,
            DateTime.UtcNow);

        await dbContext.InAppNotifications.AddAsync(record, cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);

        return new NotificationChannelSendResult(true, record.Id.ToString("D"), null, null);
    }
}
