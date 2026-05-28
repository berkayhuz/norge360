// <copyright file="DataRetentionCleanupRunner.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class DataRetentionCleanupRunner(
    AuthDbContext dbContext,
    IOptions<DataRetentionOptions> options,
    IClock clock,
    ILogger<DataRetentionCleanupRunner> logger)
{
    public async Task<DataRetentionCleanupResult> RunOnceAsync(CancellationToken cancellationToken)
    {
        var value = options.Value;
        var utcNow = clock.UtcDateTime;
        var sessionCutoff = utcNow.AddDays(-value.RevokedSessionRetentionDays);
        var auditCutoff = utcNow.AddDays(-value.AuditRetentionDays);
        var verificationTokenCutoff = utcNow.AddDays(-value.ExpiredVerificationTokenRetentionDays);
        var invitationCutoff = utcNow.AddDays(-value.ExpiredInvitationRetentionDays);
        var outboxCutoff = utcNow.AddDays(-value.PublishedOutboxRetentionDays);

        var revokedSessionCount = await dbContext.UserSessions
            .IgnoreQueryFilters()
            .Where(x => x.RevokedAt.HasValue && x.RevokedAt <= sessionCutoff && !x.IsDeleted)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.IsDeleted, true)
                .SetProperty(x => x.DeletedAt, utcNow)
                .SetProperty(x => x.DeletedBy, "retention-cleanup")
                .SetProperty(x => x.UpdatedAt, utcNow), cancellationToken);

        var oldAuditEventCount = await dbContext.AuthAuditEvents
            .IgnoreQueryFilters()
            .Where(x => x.CreatedAt <= auditCutoff && !x.IsDeleted)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.IsDeleted, true)
                .SetProperty(x => x.DeletedAt, utcNow)
                .SetProperty(x => x.DeletedBy, "retention-cleanup")
                .SetProperty(x => x.UpdatedAt, utcNow), cancellationToken);

        var expiredVerificationTokenCount = await dbContext.AuthVerificationTokens
            .IgnoreQueryFilters()
            .Where(x => x.ExpiresAtUtc <= verificationTokenCutoff && !x.IsDeleted)
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.IsDeleted, true)
                .SetProperty(x => x.DeletedAt, utcNow)
                .SetProperty(x => x.DeletedBy, "retention-cleanup")
                .SetProperty(x => x.UpdatedAt, utcNow), cancellationToken);

        var expiredInvitationCount = await dbContext.TenantInvitations
            .IgnoreQueryFilters()
            .Where(x => !x.IsDeleted &&
                        (x.ExpiresAtUtc <= invitationCutoff ||
                         (x.AcceptedAtUtc.HasValue && x.AcceptedAtUtc <= invitationCutoff) ||
                         (x.RevokedAtUtc.HasValue && x.RevokedAtUtc <= invitationCutoff)))
            .ExecuteUpdateAsync(setters => setters
                .SetProperty(x => x.IsDeleted, true)
                .SetProperty(x => x.DeletedAt, utcNow)
                .SetProperty(x => x.DeletedBy, "retention-cleanup")
                .SetProperty(x => x.UpdatedAt, utcNow), cancellationToken);

        var publishedOutboxCount = await dbContext.OutboxMessages
            .Where(x => x.PublishedAtUtc.HasValue && x.PublishedAtUtc <= outboxCutoff)
            .ExecuteDeleteAsync(cancellationToken);

        logger.LogInformation(
            "Retention cleanup completed. Soft deleted {RevokedSessionCount} sessions, {AuditEventCount} audit events, {VerificationTokenCount} verification tokens, {InvitationCount} invitations, and deleted {OutboxCount} outbox messages.",
            revokedSessionCount,
            oldAuditEventCount,
            expiredVerificationTokenCount,
            expiredInvitationCount,
            publishedOutboxCount);

        return new DataRetentionCleanupResult(
            revokedSessionCount,
            oldAuditEventCount,
            expiredVerificationTokenCount,
            expiredInvitationCount,
            publishedOutboxCount);
    }
}

public sealed record DataRetentionCleanupResult(
    int RevokedSessionCount,
    int AuditEventCount,
    int ExpiredVerificationTokenCount,
    int ExpiredInvitationCount,
    int PublishedOutboxCount);
