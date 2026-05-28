// <copyright file="EmailNotificationChannelSender.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Infrastructure.Modules.Email.Application;

namespace Norge360.Notification.Infrastructure.Channels;

public sealed class EmailNotificationChannelSender(IEmailProvider emailProvider) : INotificationChannelSender
{
    public NotificationChannel Channel => NotificationChannel.Email;
    public string ProviderName => emailProvider.Name;

    public async Task<NotificationChannelSendResult> SendAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Recipient.EmailAddress))
        {
            return new NotificationChannelSendResult(
                Succeeded: false,
                ExternalMessageId: null,
                ErrorCode: "email_recipient_missing",
                ErrorMessage: "Email channel requires recipient email address.");
        }

        var emailMessage = new EmailMessage(
            request.Recipient.EmailAddress,
            request.Subject,
            request.HtmlBody ?? request.TextBody,
            request.TextBody,
            request.CorrelationId);

        await emailProvider.SendAsync(emailMessage, cancellationToken);
        return new NotificationChannelSendResult(true, null, null, null);
    }
}
