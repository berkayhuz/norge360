// <copyright file="NotificationDeliveryAttempt.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Domain.Enums;

namespace Norge360.Notification.Domain.Entities;

public sealed class NotificationDeliveryAttempt
{
    private NotificationDeliveryAttempt()
    {
        Provider = string.Empty;
    }

    public NotificationDeliveryAttempt(
        Guid id,
        Guid notificationMessageId,
        NotificationChannel channel,
        NotificationDeliveryStatus status,
        string provider,
        string? recipient,
        string? externalMessageId,
        string? errorCode,
        string? errorMessage,
        int attemptCount,
        DateTime createdAtUtc)
    {
        Id = id;
        NotificationMessageId = notificationMessageId;
        Channel = channel;
        Status = status;
        Provider = provider;
        Recipient = recipient;
        ExternalMessageId = externalMessageId;
        ErrorCode = errorCode;
        ErrorMessage = errorMessage;
        AttemptCount = attemptCount;
        CreatedAtUtc = createdAtUtc;
    }

    public Guid Id { get; private set; }
    public Guid NotificationMessageId { get; private set; }
    public NotificationChannel Channel { get; private set; }
    public NotificationDeliveryStatus Status { get; private set; }
    public string Provider { get; private set; }
    public string? Recipient { get; private set; }
    public string? ExternalMessageId { get; private set; }
    public string? ErrorCode { get; private set; }
    public string? ErrorMessage { get; private set; }
    public int AttemptCount { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public NotificationMessage? NotificationMessage { get; private set; }
}
