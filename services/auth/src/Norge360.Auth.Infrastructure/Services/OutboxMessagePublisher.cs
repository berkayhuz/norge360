// <copyright file="OutboxMessagePublisher.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Clock;
using Norge360.Messaging.Abstractions;
using Norge360.Messaging.RabbitMq.Options;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class OutboxMessagePublisher(
    AuthDbContext dbContext,
    IIntegrationEventPublisher publisher,
    OutboxPayloadProtector payloadProtector,
    IOptions<OutboxOptions> options,
    IOptions<RabbitMqOptions> rabbitMqOptions,
    IClock clock,
    ILogger<OutboxMessagePublisher> logger)
{
    public async Task<int> PublishBatchAsync(CancellationToken cancellationToken)
    {
        var outboxOptions = options.Value;
        var utcNow = clock.UtcDateTime;
        var lockId = Guid.NewGuid();
        var lockedUntil = utcNow.AddSeconds(outboxOptions.LockSeconds);

        var candidateIds = await dbContext.OutboxMessages
            .Where(x => x.PublishedAtUtc == null)
            .Where(x => x.Attempts < outboxOptions.MaxAttempts)
            .Where(x => x.NextAttemptAtUtc == null || x.NextAttemptAtUtc <= utcNow)
            .Where(x => x.LockedUntilUtc == null || x.LockedUntilUtc <= utcNow)
            .OrderBy(x => x.CreatedAtUtc)
            .Select(x => x.Id)
            .Take(outboxOptions.BatchSize)
            .ToArrayAsync(cancellationToken);

        if (candidateIds.Length == 0)
        {
            return 0;
        }

        await dbContext.OutboxMessages
            .Where(x => candidateIds.Contains(x.Id))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.LockId, lockId)
                .SetProperty(x => x.LockedUntilUtc, lockedUntil), cancellationToken);

        dbContext.ChangeTracker.Clear();

        var messages = await dbContext.OutboxMessages
            .Where(x => x.LockId == lockId)
            .OrderBy(x => x.CreatedAtUtc)
            .ToArrayAsync(cancellationToken);

        var publishedCount = 0;
        foreach (var message in messages)
        {
            try
            {
                await publisher.PublishAsync(
                    rabbitMqOptions.Value.Exchange,
                    message.RoutingKey,
                    new IntegrationMessage(
                        new IntegrationEventMetadata(
                            message.EventId,
                            message.EventName,
                            message.EventVersion,
                            message.Source,
                            message.OccurredAtUtc,
                            message.CorrelationId,
                            message.TraceId),
                        payloadProtector.UnprotectForPublish(message.Payload)),
                    cancellationToken);

                message.PublishedAtUtc = clock.UtcDateTime;
                message.LockId = null;
                message.LockedUntilUtc = null;
                message.LastError = null;
                publishedCount++;
            }
            catch (Exception exception)
            {
                message.Attempts++;
                message.LastError = $"{exception.GetType().FullName}: outbox publish failed.";
                message.LockId = null;
                message.LockedUntilUtc = null;
                message.NextAttemptAtUtc = clock.UtcDateTime.Add(ComputeBackoff(message.Attempts));

                logger.LogError(
                    "Outbox publish failed. EventId={EventId} EventName={EventName} Attempts={Attempts} ExceptionType={ExceptionType}",
                    message.EventId,
                    message.EventName,
                    message.Attempts,
                    exception.GetType().FullName);
            }
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return publishedCount;
    }

    private static TimeSpan ComputeBackoff(int attempts)
    {
        var seconds = Math.Min(300, Math.Pow(2, Math.Min(attempts, 8)));
        return TimeSpan.FromSeconds(seconds);
    }
}
