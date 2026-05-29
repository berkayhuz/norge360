// <copyright file="NotificationQueueMessage.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Infrastructure.Queues;

public sealed record NotificationQueueMessage(
    Guid Id,
    Guid? UserId,
    NotificationCategory Category,
    NotificationPriority Priority,
    string Subject,
    string TextBody,
    string? HtmlBody,
    string? TemplateKey,
    string ChannelsJson,
    string? RecipientEmailAddress,
    string? RecipientPhoneNumber,
    string? RecipientPushToken,
    string? RecipientDisplayName,
    string MetadataJson,
    string? CorrelationId,
    string? IdempotencyKey,
    DateTime CreatedAtUtc)
{
    public static NotificationQueueMessage From(NotificationMessage message) =>
        new(
            message.Id,
            message.UserId,
            message.Category,
            message.Priority,
            message.Subject,
            message.TextBody,
            message.HtmlBody,
            message.TemplateKey,
            message.ChannelsJson,
            message.RecipientEmailAddress,
            message.RecipientPhoneNumber,
            message.RecipientPushToken,
            message.RecipientDisplayName,
            message.MetadataJson,
            message.CorrelationId,
            message.IdempotencyKey,
            message.CreatedAtUtc);

    public NotificationMessage ToDomainMessage() =>
        new(
            Id,
            UserId,
            Category,
            Priority,
            Subject,
            TextBody,
            HtmlBody,
            TemplateKey,
            ChannelsJson,
            RecipientEmailAddress,
            RecipientPhoneNumber,
            RecipientPushToken,
            RecipientDisplayName,
            MetadataJson,
            CorrelationId,
            IdempotencyKey,
            CreatedAtUtc);
}
