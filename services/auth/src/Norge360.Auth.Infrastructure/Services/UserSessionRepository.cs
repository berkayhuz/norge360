// <copyright file="UserSessionRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class UserSessionRepository(AuthDbContext dbContext) : IUserSessionRepository
{
    public Task<UserSession?> GetAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken) =>
        dbContext.UserSessions.SingleOrDefaultAsync(x => x.TenantId == tenantId && x.Id == sessionId && !x.IsDeleted, cancellationToken);

    public Task<UserSession?> GetWithUserAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken) =>
        dbContext.UserSessions
            .Include(x => x.User)
            .SingleOrDefaultAsync(x => x.TenantId == tenantId && x.Id == sessionId && !x.IsDeleted, cancellationToken);

    public async Task<IReadOnlyCollection<UserSession>> ListForUserAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
        await dbContext.UserSessions
            .Where(x => x.TenantId == tenantId && x.UserId == userId && !x.IsDeleted)
            .OrderByDescending(x => x.LastSeenAt ?? x.CreatedAt)
            .ToListAsync(cancellationToken);

    public async Task AddAsync(UserSession session, CancellationToken cancellationToken) =>
        await dbContext.UserSessions.AddAsync(session, cancellationToken);

    public async Task<bool> RevokeAsync(
        Guid tenantId,
        Guid userId,
        Guid sessionId,
        DateTime utcNow,
        string reason,
        CancellationToken cancellationToken)
    {
        var session = await dbContext.UserSessions.SingleOrDefaultAsync(
            x => x.TenantId == tenantId && x.UserId == userId && x.Id == sessionId && !x.IsDeleted,
            cancellationToken);

        if (session is null)
        {
            return false;
        }

        if (!session.IsRevoked)
        {
            session.Revoke(utcNow, reason);
        }

        return true;
    }

    public async Task<IReadOnlyCollection<Guid>> RevokeAllAsync(
        Guid tenantId,
        Guid userId,
        DateTime utcNow,
        string reason,
        Guid? excludedSessionId,
        CancellationToken cancellationToken)
    {
        var sessions = await dbContext.UserSessions
            .Where(x =>
                x.TenantId == tenantId &&
                x.UserId == userId &&
                !x.IsDeleted &&
                x.RevokedAt == null &&
                (!excludedSessionId.HasValue || x.Id != excludedSessionId.Value))
            .ToListAsync(cancellationToken);

        foreach (var session in sessions)
        {
            session.Revoke(utcNow, reason);
        }

        return sessions.Select(session => session.Id).ToArray();
    }
}
