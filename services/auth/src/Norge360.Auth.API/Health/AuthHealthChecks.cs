// <copyright file="AuthHealthChecks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Norge360.AspNetCore.TrustedGateway.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.API.Health;

public sealed class AuthDatabaseConnectivityHealthCheck(AuthDbContext dbContext) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        return await dbContext.Database.CanConnectAsync(cancellationToken)
            ? HealthCheckResult.Healthy("Identity database is reachable.")
            : HealthCheckResult.Unhealthy("Identity database is unreachable.");
    }
}

public sealed class AuthDatabaseQueryHealthCheck(AuthDbContext dbContext) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        await using var connection = dbContext.Database.GetDbConnection();
        if (connection.State != ConnectionState.Open)
        {
            await connection.OpenAsync(cancellationToken);
        }

        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT 1";
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is null ? HealthCheckResult.Unhealthy("Identity database validation query failed.") : HealthCheckResult.Healthy("Identity database validation query succeeded.");
    }
}

public sealed class AuthPendingMigrationsHealthCheck(AuthDbContext dbContext) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var pending = await dbContext.Database.GetPendingMigrationsAsync(cancellationToken);
        var pendingMigrations = pending.ToArray();

        return pendingMigrations.Length == 0
            ? HealthCheckResult.Healthy("No pending migrations.")
            : HealthCheckResult.Unhealthy($"Pending migrations detected: {string.Join(',', pendingMigrations)}");
    }
}

public sealed class DistributedCacheAvailabilityHealthCheck(IDistributedCache distributedCache) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var key = $"health:distributed-cache:{Guid.NewGuid():N}";
        await distributedCache.SetStringAsync(key, "1", new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(30)
        }, cancellationToken);

        var value = await distributedCache.GetStringAsync(key, cancellationToken);
        await distributedCache.RemoveAsync(key, cancellationToken);

        return string.Equals(value, "1", StringComparison.Ordinal)
            ? HealthCheckResult.Healthy("Distributed cache is reachable.")
            : HealthCheckResult.Unhealthy("Distributed cache roundtrip failed.");
    }
}

public sealed class JwtSigningKeyHealthCheck(ITokenSigningKeyProvider tokenSigningKeyProvider) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var current = tokenSigningKeyProvider.CurrentKeyId;
        var validationKeys = tokenSigningKeyProvider.GetValidationKeys();
        return Task.FromResult(string.IsNullOrWhiteSpace(current) || validationKeys.Count == 0
            ? HealthCheckResult.Unhealthy("JWT signing keys are unavailable.")
            : HealthCheckResult.Healthy("JWT signing keys are available."));
    }
}

public sealed class TrustedGatewayConfigurationHealthCheck(IOptions<TrustedGatewayOptions> options) : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        var value = options.Value;
        if (!value.RequireTrustedGateway)
        {
            return Task.FromResult(HealthCheckResult.Healthy("Trusted gateway requirement is disabled."));
        }

        var enabledKeys = value.Keys.Where(x => x.Enabled).ToArray();
        return Task.FromResult(enabledKeys.Length == 0 || value.AllowedSources.Length == 0
            ? HealthCheckResult.Unhealthy("Trusted gateway keys or allowed sources are missing.")
            : HealthCheckResult.Healthy("Trusted gateway configuration is loaded."));
    }
}
