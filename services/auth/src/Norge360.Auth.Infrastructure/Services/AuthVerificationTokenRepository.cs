// <copyright file="AuthVerificationTokenRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class AuthVerificationTokenRepository(AuthDbContext dbContext) : IAuthVerificationTokenRepository
{
    public async Task AddAsync(AuthVerificationToken token, CancellationToken cancellationToken) =>
        await dbContext.AuthVerificationTokens.AddAsync(token, cancellationToken);

    public Task<AuthVerificationToken?> GetValidAsync(
        Guid tenantId,
        Guid userId,
        string purpose,
        string tokenHash,
        DateTime utcNow,
        CancellationToken cancellationToken) =>
        dbContext.AuthVerificationTokens
            .SingleOrDefaultAsync(
                x => x.TenantId == tenantId &&
                     x.UserId == userId &&
                     x.Purpose == purpose &&
                     x.TokenHash == tokenHash &&
                     x.ConsumedAtUtc == null &&
                     x.ExpiresAtUtc > utcNow &&
                     !x.IsDeleted,
                cancellationToken);

    public async Task RevokeOutstandingAsync(
        Guid tenantId,
        Guid userId,
        string purpose,
        DateTime utcNow,
        string? target,
        CancellationToken cancellationToken)
    {
        var tokens = await dbContext.AuthVerificationTokens
            .Where(x =>
                x.TenantId == tenantId &&
                x.UserId == userId &&
                x.Purpose == purpose &&
                x.ConsumedAtUtc == null &&
                !x.IsDeleted &&
                (target == null || x.Target == target))
            .ToListAsync(cancellationToken);

        foreach (var token in tokens)
        {
            token.Consume(utcNow, "revoked");
        }
    }
}
