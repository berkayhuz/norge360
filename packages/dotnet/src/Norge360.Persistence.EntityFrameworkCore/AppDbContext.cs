// <copyright file="AppDbContext.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using Norge360.Entities.Abstractions;
using Norge360.Repository;
using Norge360.Tenancy;

namespace Norge360.Persistence.EntityFrameworkCore;

public abstract class AppDbContext(DbContextOptions options, ITenantContext? tenantContext = null) : DbContext(options), IUnitOfWork
{
    protected ITenantContext? TenantContext { get; } = tenantContext;
    public Guid? CurrentTenantId => TenantContext?.TenantId;

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        foreach (var entityType in modelBuilder.Model.GetEntityTypes())
        {
            if (!typeof(ITenantEntity).IsAssignableFrom(entityType.ClrType) &&
                !typeof(ISoftDeletable).IsAssignableFrom(entityType.ClrType))
            {
                continue;
            }

            var parameter = Expression.Parameter(entityType.ClrType, "entity");
            Expression? filterBody = null;

            if (typeof(ITenantEntity).IsAssignableFrom(entityType.ClrType))
            {
                var tenantProperty = Expression.Convert(
                    Expression.Property(parameter, nameof(ITenantEntity.TenantId)),
                    typeof(Guid?));
                var currentTenantProperty = Expression.Property(Expression.Constant(this), nameof(CurrentTenantId));
                var hasTenant = Expression.NotEqual(currentTenantProperty, Expression.Constant(null, typeof(Guid?)));
                var tenantMatches = Expression.Equal(tenantProperty, currentTenantProperty);
                filterBody = Expression.AndAlso(hasTenant, tenantMatches);
            }

            if (typeof(ISoftDeletable).IsAssignableFrom(entityType.ClrType))
            {
                var isDeletedProperty = Expression.Property(parameter, nameof(ISoftDeletable.IsDeleted));
                var notDeleted = Expression.Equal(isDeletedProperty, Expression.Constant(false));
                filterBody = filterBody is null ? notDeleted : Expression.AndAlso(filterBody, notDeleted);
            }

            var filter = Expression.Lambda(filterBody!, parameter);

            modelBuilder.Entity(entityType.ClrType).HasQueryFilter(filter);
        }

        base.OnModelCreating(modelBuilder);
    }
}
