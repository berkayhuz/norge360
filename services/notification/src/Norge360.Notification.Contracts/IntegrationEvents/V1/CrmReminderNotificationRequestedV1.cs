// <copyright file="CrmReminderNotificationRequestedV1.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Models;

namespace Norge360.Notification.Contracts.IntegrationEvents.V1;

public sealed record CrmReminderNotificationRequestedV1(
    Guid EventId,
    Guid TenantId,
    Guid UserId,
    NotificationRecipient Recipient,
    string ReminderType,
    Guid? RelatedEntityId,
    string? RelatedEntityType,
    IReadOnlyCollection<NotificationChannel> Channels,
    string Subject,
    string TextBody,
    string? HtmlBody,
    NotificationTemplateData Template,
    IReadOnlyDictionary<string, string> Metadata,
    string? CorrelationId,
    string? IdempotencyKey,
    DateTime DueAtUtc,
    DateTime OccurredAtUtc)
{
    public const string EventName = "notification.crm_reminder.requested";
    public const int EventVersion = 1;
    public const string RoutingKey = "notification.crm.reminder.requested.v1";
}
