// <copyright file="NotificationRabbitMqHealthCheck.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Diagnostics.HealthChecks;
using Norge360.Notification.Application.Abstractions;

namespace Norge360.Notification.Worker.Health;

public sealed class NotificationRabbitMqHealthCheck(INotificationQueue queue) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        return CheckAsync(cancellationToken);
    }

    private async Task<HealthCheckResult> CheckAsync(CancellationToken cancellationToken)
    {
        if (queue is not INotificationQueueHealthCheck healthCheck)
        {
            return HealthCheckResult.Degraded("Notification queue does not expose readiness checks.");
        }

        return await healthCheck.CanConnectAsync(cancellationToken)
            ? HealthCheckResult.Healthy("Notification RabbitMQ queue is reachable.")
            : HealthCheckResult.Unhealthy("Notification RabbitMQ queue is unreachable.");
    }
}
