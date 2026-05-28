// <copyright file="DefaultNotificationChannelPolicy.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Logging;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Contracts.Notifications.Enums;
using Norge360.Notification.Contracts.Notifications.Requests;

namespace Norge360.Notification.Application.Services;

public sealed class DefaultNotificationChannelPolicy(
    IUserNotificationPreferenceReader preferenceReader,
    ILogger<DefaultNotificationChannelPolicy> logger) : INotificationChannelPolicy
{
    public async Task<IReadOnlyCollection<NotificationChannel>> ResolveChannelsAsync(
        SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Category == NotificationCategory.Security)
        {
            return request.Channels.Distinct().ToArray();
        }

        if (request.Recipient.UserId is null)
        {
            return request.Channels.Distinct().ToArray();
        }

        var enabledChannels = new List<NotificationChannel>();
        foreach (var channel in request.Channels.Distinct())
        {
            if (await preferenceReader.IsChannelEnabledAsync(
                    request.TenantId,
                    request.Recipient.UserId.Value,
                    request.Category,
                    channel,
                    cancellationToken))
            {
                enabledChannels.Add(channel);
            }
        }

        if (enabledChannels.Count == 0 && request.Channels.Contains(NotificationChannel.InApp))
        {
            logger.LogInformation(
                "All notification channels disabled by preferences; falling back to InApp. UserId={UserId} Category={Category}",
                request.Recipient.UserId,
                request.Category);
            enabledChannels.Add(NotificationChannel.InApp);
        }

        return enabledChannels;
    }
}
