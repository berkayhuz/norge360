// <copyright file="NotificationQueueConsumerService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Options;
using Norge360.Notification.Application.Abstractions;
using Norge360.Notification.Domain.Entities;

namespace Norge360.Notification.Worker.Workers;

public sealed class NotificationQueueConsumerService(
    IServiceScopeFactory scopeFactory,
    INotificationQueue queue,
    NotificationWorkerMetrics workerMetrics,
    IOptions<NotificationWorkerOptions> options,
    ILogger<NotificationQueueConsumerService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var workerOptions = options.Value;
        using var concurrency = new SemaphoreSlim(workerOptions.MaxConcurrentMessages, workerOptions.MaxConcurrentMessages);
        var runningTasks = new List<Task>();

        logger.LogInformation(
            "Notification queue consumer started. MaxConcurrentMessages={MaxConcurrentMessages}",
            workerOptions.MaxConcurrentMessages);

        while (!stoppingToken.IsCancellationRequested)
        {
            runningTasks.RemoveAll(task => task.IsCompleted);
            await concurrency.WaitAsync(stoppingToken);

            var message = await queue.DequeueAsync(stoppingToken);
            if (message is null)
            {
                concurrency.Release();
                await Task.Delay(TimeSpan.FromMilliseconds(workerOptions.EmptyQueueDelayMilliseconds), stoppingToken);
                continue;
            }

            runningTasks.Add(ProcessMessageAsync(message, concurrency, workerOptions, stoppingToken));
        }

        await Task.WhenAll(runningTasks);
    }

    private async Task ProcessMessageAsync(
        NotificationMessage message,
        SemaphoreSlim concurrency,
        NotificationWorkerOptions workerOptions,
        CancellationToken stoppingToken)
    {
        try
        {
            try
            {
                logger.LogInformation(
                    "Dequeued notification. NotificationId={NotificationId} CorrelationId={CorrelationId}",
                    message.Id,
                    message.CorrelationId);

                using var scope = scopeFactory.CreateScope();
                var processor = scope.ServiceProvider.GetRequiredService<INotificationProcessor>();
                await processor.ProcessAsync(message, stoppingToken);
                await queue.CompleteAsync(message, stoppingToken);
                workerMetrics.RecordDeliveryLatency(DateTime.UtcNow - message.CreatedAtUtc);

                logger.LogInformation(
                    "Notification processing completed. NotificationId={NotificationId}",
                    message.Id);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                await queue.AbandonAsync(message, requeue: true, CancellationToken.None);
                throw;
            }
            catch (Exception exception)
            {
                logger.LogError(
                    exception,
                    "Notification processing failed and message will be requeued. NotificationId={NotificationId}",
                    message.Id);

                await queue.AbandonAsync(
                    message,
                    requeue: !workerOptions.DeadLetterUnexpectedFailures,
                    stoppingToken);
                if (workerOptions.DeadLetterUnexpectedFailures)
                {
                    workerMetrics.RecordDeadLetter();
                }
                else
                {
                    workerMetrics.RecordRetry();
                }
            }
        }
        finally
        {
            concurrency.Release();
        }
    }
}
