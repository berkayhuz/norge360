// <copyright file="NotificationDispatcher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Text.Json;
using Microsoft.Extensions.Logging;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Requests;
using Norge360.Notification.Contracts.Notifications.Responses;

namespace Norge360.Notification.Application.Services;

public sealed class NotificationDispatcher(
    INotificationDeliveryLog deliveryLog,
    INotificationQueue queue,
    INotificationTemplateRenderer templateRenderer,
    INotificationChannelPolicy channelPolicy,
    NotificationMetrics metrics,
    ILogger<NotificationDispatcher> logger) : INotificationDispatcher
{
    public async Task<SendNotificationResponse> SendAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken = default)
    {
        Validate(request);
        var renderedRequest = templateRenderer.Render(request);
        var resolvedChannels = await channelPolicy.ResolveChannelsAsync(renderedRequest, cancellationToken);
        var dispatchRequest = renderedRequest with { Channels = resolvedChannels };

        Validate(dispatchRequest);

        var notification = await deliveryLog.CreateNotificationAsync(dispatchRequest, cancellationToken);
        await queue.EnqueueAsync(notification, cancellationToken);
        await deliveryLog.MarkQueuedAsync(notification.Id, cancellationToken);
        metrics.NotificationEnqueued(notification.Category);

        logger.LogInformation(
            "Notification enqueued. NotificationId={NotificationId} CorrelationId={CorrelationId} Channels={Channels}",
            notification.Id,
            notification.CorrelationId,
            notification.ChannelsJson);

        return new SendNotificationResponse(notification.Id, Accepted: true, []);
    }

    private static void Validate(SendNotificationRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (request.Channels.Count == 0)
        {
            throw new ArgumentException("At least one notification channel must be selected.", nameof(request));
        }

        if (string.IsNullOrWhiteSpace(request.Subject))
        {
            throw new ArgumentException("Notification subject is required.", nameof(request));
        }

        if (string.IsNullOrWhiteSpace(request.TextBody))
        {
            throw new ArgumentException("Notification text body is required.", nameof(request));
        }

        JsonSerializer.Serialize(request.Metadata);
    }
}
