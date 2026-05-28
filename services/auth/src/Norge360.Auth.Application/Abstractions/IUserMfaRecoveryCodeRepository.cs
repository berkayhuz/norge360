// <copyright file="IUserMfaRecoveryCodeRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface IUserMfaRecoveryCodeRepository
{
    Task<int> CountActiveAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task<bool> ConsumeAsync(Guid tenantId, Guid userId, string codeHash, DateTime utcNow, CancellationToken cancellationToken);
    Task ReplaceActiveAsync(Guid tenantId, Guid userId, IReadOnlyCollection<UserMfaRecoveryCode> recoveryCodes, DateTime utcNow, CancellationToken cancellationToken);
    Task RevokeActiveAsync(Guid tenantId, Guid userId, DateTime utcNow, CancellationToken cancellationToken);
}
