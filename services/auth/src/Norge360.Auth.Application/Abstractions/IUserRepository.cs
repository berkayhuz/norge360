// <copyright file="IUserRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface IUserRepository
{
    Task<User?> FindByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken);
    Task<User?> GetActiveByIdAsync(Guid userId, CancellationToken cancellationToken);
    Task<User?> GetByIdAsync(Guid userId, CancellationToken cancellationToken);
    Task<ActiveUserTokenState?> GetActiveTokenStateAsync(Guid userId, CancellationToken cancellationToken);
    Task<bool> ExistsByUserNameAsync(string normalizedUserName, CancellationToken cancellationToken);
    Task<bool> ExistsByEmailAsync(string normalizedEmail, CancellationToken cancellationToken);
    Task RecordFailedLoginAsync(Guid userId, int maxFailedAttempts, DateTime lockoutEndAt, DateTime utcNow, CancellationToken cancellationToken);
    Task AddAsync(User user, CancellationToken cancellationToken);
}

public sealed record ActiveUserTokenState(int TokenVersion);
