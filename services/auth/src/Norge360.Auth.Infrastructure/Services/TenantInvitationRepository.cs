// <copyright file="TenantInvitationRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class TenantInvitationRepository(AuthDbContext dbContext) : ITenantInvitationRepository
{
    public Task<TenantInvitation?> GetPendingByTokenHashAsync(
        Guid tenantId,
        string tokenHash,
        DateTime utcNow,
        CancellationToken cancellationToken) =>
        dbContext.TenantInvitations.SingleOrDefaultAsync(
            x => x.TenantId == tenantId &&
                 x.TokenHash == tokenHash &&
                 x.AcceptedAtUtc == null &&
                 x.ExpiresAtUtc > utcNow &&
                 !x.IsDeleted &&
                 x.IsActive,
            cancellationToken);

    public Task<bool> HasPendingInviteForEmailAsync(
        Guid tenantId,
        string normalizedEmail,
        DateTime utcNow,
        CancellationToken cancellationToken) =>
        dbContext.TenantInvitations.AnyAsync(
            x => x.TenantId == tenantId &&
                 x.NormalizedEmail == normalizedEmail &&
                 x.AcceptedAtUtc == null &&
                 x.ExpiresAtUtc > utcNow &&
                 !x.IsDeleted &&
                 x.IsActive,
            cancellationToken);

    public async Task<TenantInvitation?> GetByIdAsync(Guid tenantId, Guid invitationId, CancellationToken cancellationToken) =>
        await dbContext.TenantInvitations.SingleOrDefaultAsync(
            x => x.TenantId == tenantId && x.Id == invitationId,
            cancellationToken);

    public async Task<IReadOnlyCollection<TenantInvitation>> ListForTenantAsync(Guid tenantId, CancellationToken cancellationToken) =>
        await dbContext.TenantInvitations
            .Where(x => x.TenantId == tenantId)
            .OrderByDescending(x => x.CreatedAt)
            .Take(100)
            .ToListAsync(cancellationToken);

    public async Task AddAsync(TenantInvitation invitation, CancellationToken cancellationToken) =>
        await dbContext.TenantInvitations.AddAsync(invitation, cancellationToken);
}
