// <copyright file="OutboxInviteNotificationDispatcher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class OutboxInviteNotificationDispatcher(
    IIntegrationEventOutbox outbox,
    IOptions<InvitationDeliveryOptions> options) : IInviteNotificationDispatcher
{
    public Task SendInviteCreatedAsync(
        Tenant tenant,
        TenantInvitation invitation,
        User inviter,
        User? invitedUser,
        string rawToken,
        string? correlationId,
        string? traceId,
        DateTime utcNow,
        CancellationToken cancellationToken) =>
        EnqueueAsync(tenant, invitation, inviter, invitedUser, rawToken, "created", correlationId, traceId, utcNow, cancellationToken);

    public Task SendInviteResentAsync(
        Tenant tenant,
        TenantInvitation invitation,
        User inviter,
        User? invitedUser,
        string rawToken,
        string? correlationId,
        string? traceId,
        DateTime utcNow,
        CancellationToken cancellationToken) =>
        EnqueueAsync(tenant, invitation, inviter, invitedUser, rawToken, "resent", correlationId, traceId, utcNow, cancellationToken);

    private Task EnqueueAsync(
        Tenant tenant,
        TenantInvitation invitation,
        User inviter,
        User? invitedUser,
        string rawToken,
        string deliveryReason,
        string? correlationId,
        string? traceId,
        DateTime utcNow,
        CancellationToken cancellationToken)
    {
        var invitationUrl = options.Value.BuildAcceptUrl(tenant.Id, rawToken, invitation.Email);
        var inviterDisplayName = DisplayName(inviter);
        var metadata = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["inviterDisplayName"] = inviterDisplayName,
            ["tenantName"] = tenant.Name,
            ["invitationUrl"] = invitationUrl,
            ["invitationId"] = invitation.Id.ToString("D"),
            ["deliveryReason"] = deliveryReason,
            ["expiresAtUtc"] = invitation.ExpiresAtUtc.ToString("O")
        };

        var payload = new NotificationRequestedPayloadV1(
            Guid.NewGuid(),
            tenant.Id,
            invitedUser?.Id,
            "Norge360.Auth",
            NotificationCategory.Account,
            NotificationPriority.High,
            new NotificationRecipient(
                invitedUser?.Id,
                invitation.Email,
                null,
                null,
                invitation.FirstName ?? invitation.Email),
            invitedUser is null
                ? [NotificationChannel.Email]
                : [NotificationChannel.InApp, NotificationChannel.Email],
            "{{inviterDisplayName}} invited you to {{tenantName}} on Norge360",
            "Accept your invitation: {{invitationUrl}}",
            "<p>{{inviterDisplayName}} invited you to <strong>{{tenantName}}</strong> on Norge360.</p><p><a href=\"{{invitationUrl}}\">Accept your invitation</a></p><p>This invitation expires at {{expiresAtUtc}}.</p>",
            new NotificationTemplateData("auth.tenant_invitation.v1", metadata),
            metadata,
            correlationId,
            $"{invitation.Id:N}:{deliveryReason}",
            utcNow);

        return outbox.AddAsync(
            Guid.NewGuid(),
            NotificationRequestedPayloadV1.EventName,
            NotificationRequestedPayloadV1.EventVersion,
            NotificationRequestedPayloadV1.RoutingKey,
            "Norge360.Auth",
            payload,
            correlationId,
            traceId,
            utcNow,
            cancellationToken);
    }

    private static string DisplayName(User user)
    {
        var value = string.Join(' ', new[] { user.FirstName, user.LastName }.Where(x => !string.IsNullOrWhiteSpace(x)));
        return string.IsNullOrWhiteSpace(value) ? user.Email ?? user.UserName : value;
    }

    private sealed record NotificationRequestedPayloadV1(
        Guid EventId,
        Guid? TenantId,
        Guid? UserId,
        string Source,
        NotificationCategory Category,
        NotificationPriority Priority,
        NotificationRecipient Recipient,
        IReadOnlyCollection<NotificationChannel> Channels,
        string Subject,
        string TextBody,
        string? HtmlBody,
        NotificationTemplateData Template,
        IReadOnlyDictionary<string, string> Metadata,
        string? CorrelationId,
        string? IdempotencyKey,
        DateTime OccurredAtUtc)
    {
        public const string EventName = "notification.requested";
        public const int EventVersion = 1;
        public const string RoutingKey = "notification.requested.v1";
    }

    private sealed record NotificationRecipient(
        Guid? UserId,
        string? EmailAddress,
        string? PhoneNumber,
        string? PushToken,
        string? DisplayName);

    private sealed record NotificationTemplateData(
        string? TemplateKey,
        IReadOnlyDictionary<string, string> Values);

    private enum NotificationCategory
    {
        Account = 2
    }

    private enum NotificationPriority
    {
        High = 3
    }

    private enum NotificationChannel
    {
        Email = 1,
        InApp = 4
    }
}
