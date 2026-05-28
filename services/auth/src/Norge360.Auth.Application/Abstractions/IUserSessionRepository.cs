// <copyright file="IUserSessionRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface IUserSessionRepository
{
    Task<UserSession?> GetAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken);
    Task<UserSession?> GetWithUserAsync(Guid tenantId, Guid sessionId, CancellationToken cancellationToken);
    Task<IReadOnlyCollection<UserSession>> ListForUserAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task AddAsync(UserSession session, CancellationToken cancellationToken);
    Task<bool> RevokeAsync(Guid tenantId, Guid userId, Guid sessionId, DateTime utcNow, string reason, CancellationToken cancellationToken);
    Task<IReadOnlyCollection<Guid>> RevokeAllAsync(Guid tenantId, Guid userId, DateTime utcNow, string reason, Guid? excludedSessionId, CancellationToken cancellationToken);
}
