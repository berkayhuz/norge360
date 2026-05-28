// <copyright file="DataRetentionCleanupService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class DataRetentionCleanupService(
    IServiceScopeFactory scopeFactory,
    IOptions<DataRetentionOptions> options,
    IClock clock,
    ILogger<DataRetentionCleanupService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var value = options.Value;
        if (!value.EnableCleanupService)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopeFactory.CreateScope();
                var dbContext = scope.ServiceProvider.GetRequiredService<AuthDbContext>();

                var utcNow = clock.UtcDateTime;
                var sessionCutoff = utcNow.AddDays(-value.RevokedSessionRetentionDays);
                var auditCutoff = utcNow.AddDays(-value.AuditRetentionDays);

                var revokedSessionCount = await dbContext.UserSessions
                    .IgnoreQueryFilters()
                    .Where(x => x.RevokedAt.HasValue && x.RevokedAt <= sessionCutoff && !x.IsDeleted)
                    .ExecuteUpdateAsync(setters => setters
                        .SetProperty(x => x.IsDeleted, true)
                        .SetProperty(x => x.DeletedAt, utcNow)
                        .SetProperty(x => x.DeletedBy, "retention-cleanup")
                        .SetProperty(x => x.UpdatedAt, utcNow), stoppingToken);

                var oldAuditEventCount = await dbContext.AuthAuditEvents
                    .IgnoreQueryFilters()
                    .Where(x => x.CreatedAt <= auditCutoff && !x.IsDeleted)
                    .ExecuteUpdateAsync(setters => setters
                        .SetProperty(x => x.IsDeleted, true)
                        .SetProperty(x => x.DeletedAt, utcNow)
                        .SetProperty(x => x.DeletedBy, "retention-cleanup")
                        .SetProperty(x => x.UpdatedAt, utcNow), stoppingToken);

                logger.LogInformation(
                    "Retention cleanup completed. Soft deleted {RevokedSessionCount} sessions and {AuditEventCount} audit events.",
                    revokedSessionCount,
                    oldAuditEventCount);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Retention cleanup failed.");
            }

            await Task.Delay(TimeSpan.FromMinutes(value.CleanupIntervalMinutes), stoppingToken);
        }
    }
}
