// <copyright file="NotificationMessage.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Domain.Enums;

namespace Norge360.Notification.Domain.Entities;

public sealed class NotificationMessage
{
    private readonly List<NotificationDeliveryAttempt> _deliveryAttempts = [];

    private NotificationMessage()
    {
        Subject = string.Empty;
        TextBody = string.Empty;
        MetadataJson = "{}";
        ChannelsJson = "[]";
    }

    public NotificationMessage(
        Guid id,
        Guid? tenantId,
        Guid? userId,
        NotificationCategory category,
        NotificationPriority priority,
        string subject,
        string textBody,
        string? htmlBody,
        string? templateKey,
        string channelsJson,
        string? recipientEmailAddress,
        string? recipientPhoneNumber,
        string? recipientPushToken,
        string? recipientDisplayName,
        string metadataJson,
        string? correlationId,
        string? idempotencyKey,
        DateTime createdAtUtc)
    {
        Id = id;
        TenantId = tenantId;
        UserId = userId;
        Category = category;
        Priority = priority;
        Subject = subject;
        TextBody = textBody;
        HtmlBody = htmlBody;
        TemplateKey = templateKey;
        ChannelsJson = channelsJson;
        RecipientEmailAddress = recipientEmailAddress;
        RecipientPhoneNumber = recipientPhoneNumber;
        RecipientPushToken = recipientPushToken;
        RecipientDisplayName = recipientDisplayName;
        MetadataJson = metadataJson;
        CorrelationId = correlationId;
        IdempotencyKey = idempotencyKey;
        CreatedAtUtc = createdAtUtc;
        Status = NotificationStatus.Pending;
    }

    public Guid Id { get; private set; }
    public Guid? TenantId { get; private set; }
    public Guid? UserId { get; private set; }
    public NotificationCategory Category { get; private set; }
    public NotificationPriority Priority { get; private set; }
    public NotificationStatus Status { get; private set; }
    public string Subject { get; private set; }
    public string TextBody { get; private set; }
    public string? HtmlBody { get; private set; }
    public string? TemplateKey { get; private set; }
    public string ChannelsJson { get; private set; }
    public string? RecipientEmailAddress { get; private set; }
    public string? RecipientPhoneNumber { get; private set; }
    public string? RecipientPushToken { get; private set; }
    public string? RecipientDisplayName { get; private set; }
    public string MetadataJson { get; private set; }
    public string? CorrelationId { get; private set; }
    public string? IdempotencyKey { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime? CompletedAtUtc { get; private set; }
    public DateTime? QueuedAtUtc { get; private set; }
    public DateTime? ProcessingStartedAtUtc { get; private set; }
    public DateTime? DeadLetteredAtUtc { get; private set; }
    public IReadOnlyCollection<NotificationDeliveryAttempt> DeliveryAttempts => _deliveryAttempts;

    public void MarkQueued(DateTime utcNow)
    {
        Status = NotificationStatus.Queued;
        QueuedAtUtc = utcNow;
    }

    public void MarkProcessing(DateTime utcNow)
    {
        Status = NotificationStatus.Processing;
        ProcessingStartedAtUtc = utcNow;
    }

    public void MarkDeadLettered(DateTime utcNow)
    {
        Status = NotificationStatus.DeadLettered;
        DeadLetteredAtUtc = utcNow;
        CompletedAtUtc = utcNow;
    }

    public void AddDeliveryAttempt(NotificationDeliveryAttempt attempt)
    {
        _deliveryAttempts.Add(attempt);
        RefreshStatus();
    }

    private void RefreshStatus()
    {
        if (_deliveryAttempts.Count == 0)
        {
            Status = NotificationStatus.Pending;
            return;
        }

        var deliveredCount = _deliveryAttempts.Count(x => x.Status == NotificationDeliveryStatus.Succeeded);
        if (deliveredCount == _deliveryAttempts.Count)
        {
            Status = NotificationStatus.Delivered;
            CompletedAtUtc = _deliveryAttempts.Max(x => x.CreatedAtUtc);
            return;
        }

        Status = deliveredCount > 0
            ? NotificationStatus.PartiallyDelivered
            : NotificationStatus.Failed;

        CompletedAtUtc = _deliveryAttempts.Max(x => x.CreatedAtUtc);
    }
}
