// <copyright file="TenantIsolationSaveChangesInterceptor.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Norge360.CurrentUser;
using Norge360.Entities.Abstractions;
using Norge360.Tenancy;

namespace Norge360.Persistence.EntityFrameworkCore.Tenancy;

public sealed class TenantIsolationSaveChangesInterceptor(
    ITenantContext? tenantContext = null,
    ITenantProvider? tenantProvider = null,
    ICurrentUserService? currentUserService = null) : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        ApplyTenant(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        ApplyTenant(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    private void ApplyTenant(DbContext? context)
    {
        if (context is null)
        {
            return;
        }

        var tenantEntries = context.ChangeTracker
            .Entries<ITenantEntity>()
            .Where(x => x.State is EntityState.Added or EntityState.Modified or EntityState.Deleted)
            .ToArray();

        if (tenantEntries.Length == 0)
        {
            return;
        }

        var tenantId = tenantContext?.TenantId ?? tenantProvider?.TenantId;
        if (tenantId is null)
        {
            if (currentUserService?.IsAuthenticated == true)
            {
                throw new InvalidOperationException("Authenticated writes require a tenant context.");
            }

            return;
        }

        foreach (EntityEntry<ITenantEntity> entry in tenantEntries)
        {
            if (entry.State == EntityState.Added && entry.Entity.TenantId == Guid.Empty)
            {
                entry.Entity.TenantId = tenantId.Value;
                continue;
            }

            if (entry.Entity.TenantId != tenantId.Value)
            {
                throw new InvalidOperationException("tenant isolation rejected an entity with a different tenant.");
            }

            var tenantProperty = entry.Metadata.FindProperty(nameof(ITenantEntity.TenantId));
            if (entry.State != EntityState.Added &&
                tenantProperty is not null &&
                entry.OriginalValues[tenantProperty] is Guid originalTenantId &&
                originalTenantId != tenantId.Value)
            {
                throw new InvalidOperationException("CRM tenant isolation rejected a cross-tenant update.");
            }
        }
    }
}
