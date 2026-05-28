// <copyright file="AuthDatabaseHealthCheck.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.Extensions.Diagnostics.HealthChecks;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.API.Health;

public sealed class AuthDatabaseHealthCheck(AuthDbContext dbContext) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        return await dbContext.Database.CanConnectAsync(cancellationToken)
            ? HealthCheckResult.Healthy("Identity database is reachable.")
            : HealthCheckResult.Unhealthy("Identity database is unreachable.");
    }
}
