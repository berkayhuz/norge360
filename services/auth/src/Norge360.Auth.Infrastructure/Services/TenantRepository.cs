// <copyright file="TenantRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class TenantRepository(AuthDbContext dbContext) : ITenantRepository
{
    public Task<Tenant?> GetByIdAsync(Guid tenantId, CancellationToken cancellationToken) =>
        dbContext.Tenants.SingleOrDefaultAsync(x => x.Id == tenantId && x.IsActive, cancellationToken);

    public Task<Tenant?> GetBySlugAsync(string slug, CancellationToken cancellationToken) =>
        dbContext.Tenants.SingleOrDefaultAsync(x => x.Slug == slug && x.IsActive, cancellationToken);

    public async Task AddAsync(Tenant tenant, CancellationToken cancellationToken) =>
        await dbContext.Tenants.AddAsync(tenant, cancellationToken);

    public Task DeactivateAsync(Tenant tenant, DateTime utcNow, Guid actorUserId, CancellationToken cancellationToken)
    {
        tenant.IsActive = false;
        tenant.UpdatedAt = utcNow;
        tenant.UpdatedBy = actorUserId.ToString("N");

        return dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenant.Id && !x.IsDeleted)
            .ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(x => x.IsActive, false)
                    .SetProperty(x => x.UpdatedAt, utcNow)
                    .SetProperty(x => x.UpdatedBy, actorUserId.ToString("N")),
                cancellationToken);
    }
}
