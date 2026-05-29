// <copyright file="IAuthVerificationTokenRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface IAuthVerificationTokenRepository
{
    Task AddAsync(AuthVerificationToken token, CancellationToken cancellationToken);
    Task<AuthVerificationToken?> GetValidAsync(
        Guid userId,
        string purpose,
        string tokenHash,
        DateTime utcNow,
        CancellationToken cancellationToken);

    Task RevokeOutstandingAsync(
        Guid userId,
        string purpose,
        DateTime utcNow,
        string? target,
        CancellationToken cancellationToken);
}
