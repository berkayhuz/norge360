// <copyright file="NotificationMetrics.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Diagnostics.Metrics;
using Norge360.Notification.Contracts.Notifications.Enums;

namespace Norge360.Notification.Application.Services;

public sealed class NotificationMetrics
{
    public const string MeterName = "Norge360.Notification";
    private readonly Meter? ownedMeter;
    private readonly Counter<long> enqueuedCounter;
    private readonly Counter<long> processedCounter;
    private readonly Counter<long> failedCounter;

    public NotificationMetrics()
        : this(new Meter(MeterName))
    {
    }

    public NotificationMetrics(IMeterFactory meterFactory)
        : this(meterFactory.Create(MeterName))
    {
    }

    private NotificationMetrics(Meter meter)
    {
        ownedMeter = meter;
        enqueuedCounter = meter.CreateCounter<long>("notification_enqueued_total");
        processedCounter = meter.CreateCounter<long>("notification_channel_processed_total");
        failedCounter = meter.CreateCounter<long>("notification_channel_failed_total");
    }

    public void NotificationEnqueued(NotificationCategory category)
    {
        enqueuedCounter.Add(1, new KeyValuePair<string, object?>("category", category.ToString()));
    }

    public void ChannelProcessed(NotificationChannel channel, bool succeeded)
    {
        processedCounter.Add(
            1,
            new KeyValuePair<string, object?>("channel", channel.ToString()),
            new KeyValuePair<string, object?>("succeeded", succeeded));

        if (!succeeded)
        {
            failedCounter.Add(1, new KeyValuePair<string, object?>("channel", channel.ToString()));
        }
    }
}
