// <copyright file="AuthSessionService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;
using Norge360.Clock;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthSessionService(
    AuthDbContext dbContext,
    IOptions<SessionSecurityOptions> options,
    IClock clock) : IAuthSessionService
{
    public async Task<IReadOnlyCollection<Guid>> EnforceSessionLimitsAsync(Guid userId, Guid? currentSessionId, CancellationToken cancellationToken)
    {
        var value = options.Value;
        var revokedSessionIds = new List<Guid>();

        var activeSessions = await dbContext.UserSessions
            .Where(x => x.UserId == userId && x.RevokedAt == null)
            .OrderByDescending(x => x.LastSeenAt ?? x.CreatedAt)
            .ToListAsync(cancellationToken);

        foreach (var expired in activeSessions.Where(x => IsExpired(x, clock.UtcDateTime)))
        {
            expired.Revoke(clock.UtcDateTime, "session_expired");
            revokedSessionIds.Add(expired.Id);
        }

        var survivors = activeSessions
            .Where(x => x.RevokedAt == null && (!currentSessionId.HasValue || x.Id != currentSessionId.Value))
            .OrderByDescending(x => x.LastSeenAt ?? x.CreatedAt)
            .ToList();

        foreach (var overflow in survivors.Skip(Math.Max(0, value.MaxActiveSessions - 1)))
        {
            overflow.Revoke(clock.UtcDateTime, "max_active_sessions_exceeded");
            revokedSessionIds.Add(overflow.Id);
        }

        return revokedSessionIds;
    }

    public bool IsExpired(UserSession session, DateTime utcNow)
    {
        var value = options.Value;
        var idleCutoff = (session.LastSeenAt ?? session.CreatedAt).AddMinutes(value.IdleTimeoutMinutes);
        var absoluteCutoff = session.CreatedAt.AddDays(value.AbsoluteLifetimeDays);
        return utcNow >= idleCutoff || utcNow >= absoluteCutoff || utcNow >= session.RefreshTokenExpiresAt;
    }
}
