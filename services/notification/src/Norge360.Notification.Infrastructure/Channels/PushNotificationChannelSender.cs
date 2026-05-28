// <copyright file="PushNotificationChannelSender.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Requests;

namespace Norge360.Notification.Infrastructure.Channels;

public sealed class PushNotificationChannelSender(IPushProvider pushProvider) : INotificationChannelSender
{
    public NotificationChannel Channel => NotificationChannel.Push;
    public string ProviderName => pushProvider.Name;

    public async Task<NotificationChannelSendResult> SendAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Recipient.PushToken))
        {
            return new NotificationChannelSendResult(
                Succeeded: false,
                ExternalMessageId: null,
                ErrorCode: "push_recipient_missing",
                ErrorMessage: "Push channel requires recipient push token.");
        }

        var externalId = await pushProvider.SendAsync(
            request.Recipient.PushToken,
            request.Subject,
            request.TextBody,
            request.CorrelationId,
            cancellationToken);

        return new NotificationChannelSendResult(true, externalId, null, null);
    }
}
