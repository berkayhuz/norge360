// <copyright file="UserMfaRecoveryCodeRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class UserMfaRecoveryCodeRepository(AuthDbContext dbContext) : IUserMfaRecoveryCodeRepository
{
    public Task<int> CountActiveAsync(Guid userId, CancellationToken cancellationToken) =>
        dbContext.UserMfaRecoveryCodes.CountAsync(
            x => x.UserId == userId && !x.IsDeleted && x.ConsumedAtUtc == null,
            cancellationToken);

    public async Task ReplaceActiveAsync(
        Guid userId,
        IReadOnlyCollection<UserMfaRecoveryCode> recoveryCodes,
        DateTime utcNow,
        CancellationToken cancellationToken)
    {
        var existing = await dbContext.UserMfaRecoveryCodes
            .Where(x => x.UserId == userId && !x.IsDeleted && x.ConsumedAtUtc == null)
            .ToListAsync(cancellationToken);

        foreach (var code in existing)
        {
            code.IsDeleted = true;
            code.DeletedAt = utcNow;
            code.UpdatedAt = utcNow;
        }

        await dbContext.UserMfaRecoveryCodes.AddRangeAsync(recoveryCodes, cancellationToken);
    }

    public async Task<bool> ConsumeAsync(Guid userId, string codeHash, DateTime utcNow, CancellationToken cancellationToken)
    {
        var entity = await dbContext.UserMfaRecoveryCodes
            .Where(x => x.UserId == userId &&
                        !x.IsDeleted &&
                        x.ConsumedAtUtc == null &&
                        x.CodeHash == codeHash)
            .SingleOrDefaultAsync(cancellationToken);
        if (entity is null)
        {
            return false;
        }

        entity.Consume(utcNow, ipAddress: null);
        return true;
    }

    public async Task RevokeActiveAsync(Guid userId, DateTime utcNow, CancellationToken cancellationToken)
    {
        var existing = await dbContext.UserMfaRecoveryCodes
            .Where(x => x.UserId == userId && !x.IsDeleted && x.ConsumedAtUtc == null)
            .ToListAsync(cancellationToken);

        foreach (var code in existing)
        {
            code.IsDeleted = true;
            code.DeletedAt = utcNow;
            code.UpdatedAt = utcNow;
        }
    }
}
