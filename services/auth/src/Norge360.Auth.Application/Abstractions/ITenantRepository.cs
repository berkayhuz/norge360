// <copyright file="ITenantRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface ITenantRepository
{
    Task<Tenant?> GetByIdAsync(Guid tenantId, CancellationToken cancellationToken);
    Task<Tenant?> GetBySlugAsync(string slug, CancellationToken cancellationToken);
    Task AddAsync(Tenant tenant, CancellationToken cancellationToken);
    Task DeactivateAsync(Tenant tenant, DateTime utcNow, Guid actorUserId, CancellationToken cancellationToken);
}
