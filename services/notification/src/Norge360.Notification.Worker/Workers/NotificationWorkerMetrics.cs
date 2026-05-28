// <copyright file="NotificationWorkerMetrics.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Diagnostics.Metrics;
using Norge360.Notification.Application.Abstractions;

namespace Norge360.Notification.Worker.Workers;

public sealed class NotificationWorkerMetrics
{
    public const string MeterName = "Norge360.Notification.Worker";
    private readonly INotificationQueueHealthCheck queueHealthCheck;
    private readonly Counter<long> retryCounter;
    private readonly Counter<long> deadLetterCounter;
    private readonly Histogram<double> deliveryLatency;
    private readonly ObservableGauge<long> queueDepthGauge;
    private readonly ObservableGauge<long> deadLetterDepthGauge;
    private readonly ObservableGauge<long> consumerLagGauge;

    public NotificationWorkerMetrics(IMeterFactory meterFactory, INotificationQueueHealthCheck queueHealthCheck)
    {
        this.queueHealthCheck = queueHealthCheck;
        var meter = meterFactory.Create(MeterName);
        retryCounter = meter.CreateCounter<long>("notification.worker.retry.total");
        deadLetterCounter = meter.CreateCounter<long>("notification.worker.dead_letter.total");
        deliveryLatency = meter.CreateHistogram<double>("notification.worker.delivery.latency.ms", unit: "ms");
        queueDepthGauge = meter.CreateObservableGauge("notification.worker.queue.depth", ObserveQueueDepth);
        deadLetterDepthGauge = meter.CreateObservableGauge("notification.worker.queue.dead_letter.depth", ObserveDeadLetterDepth);
        consumerLagGauge = meter.CreateObservableGauge("notification.worker.queue.consumer_lag", ObserveConsumerLag);
    }

    public void RecordRetry() => retryCounter.Add(1);
    public void RecordDeadLetter() => deadLetterCounter.Add(1);
    public void RecordDeliveryLatency(TimeSpan latency) => deliveryLatency.Record(latency.TotalMilliseconds);

    private IEnumerable<Measurement<long>> ObserveQueueDepth()
    {
        var snapshot = queueHealthCheck.GetSnapshotAsync(CancellationToken.None).GetAwaiter().GetResult();
        if (snapshot is null)
        {
            yield break;
        }

        yield return new Measurement<long>(snapshot.QueueDepth);
    }

    private IEnumerable<Measurement<long>> ObserveDeadLetterDepth()
    {
        var snapshot = queueHealthCheck.GetSnapshotAsync(CancellationToken.None).GetAwaiter().GetResult();
        if (snapshot is null)
        {
            yield break;
        }

        yield return new Measurement<long>(snapshot.DeadLetterDepth);
    }

    private IEnumerable<Measurement<long>> ObserveConsumerLag()
    {
        var snapshot = queueHealthCheck.GetSnapshotAsync(CancellationToken.None).GetAwaiter().GetResult();
        if (snapshot is null)
        {
            yield break;
        }

        var consumerCount = Math.Max(snapshot.ConsumerCount, 1);
        var lag = Math.Max(snapshot.QueueDepth - consumerCount, 0);
        yield return new Measurement<long>(lag);
    }
}
