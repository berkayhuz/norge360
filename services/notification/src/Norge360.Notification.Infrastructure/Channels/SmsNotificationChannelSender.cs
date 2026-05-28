// <copyright file="SmsNotificationChannelSender.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Requests;

namespace Norge360.Notification.Infrastructure.Channels;

public sealed class SmsNotificationChannelSender(ISmsProvider smsProvider) : INotificationChannelSender
{
    public NotificationChannel Channel => NotificationChannel.Sms;
    public string ProviderName => smsProvider.Name;

    public async Task<NotificationChannelSendResult> SendAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Recipient.PhoneNumber))
        {
            return new NotificationChannelSendResult(
                Succeeded: false,
                ExternalMessageId: null,
                ErrorCode: "sms_recipient_missing",
                ErrorMessage: "SMS channel requires recipient phone number.");
        }

        var externalId = await smsProvider.SendAsync(
            request.Recipient.PhoneNumber,
            request.TextBody,
            request.CorrelationId,
            cancellationToken);

        return new NotificationChannelSendResult(true, externalId, null, null);
    }
}
