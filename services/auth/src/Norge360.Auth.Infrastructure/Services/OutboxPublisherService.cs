// <copyright file="OutboxPublisherService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class OutboxPublisherService(
    IServiceScopeFactory scopeFactory,
    IOptions<OutboxOptions> options,
    ILogger<OutboxPublisherService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var outboxOptions = options.Value;
        if (!outboxOptions.EnablePublisher)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var publisher = scope.ServiceProvider.GetRequiredService<OutboxMessagePublisher>();
                await publisher.PublishBatchAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Outbox publisher batch failed.");
            }

            await Task.Delay(TimeSpan.FromSeconds(outboxOptions.PollingIntervalSeconds), stoppingToken);
        }
    }
}
