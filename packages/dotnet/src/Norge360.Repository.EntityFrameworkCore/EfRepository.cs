// <copyright file="EfRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;

namespace Norge360.Repository.EntityFrameworkCore;

public sealed class EfRepository<TEntity, TKey>(DbContext dbContext) : IRepository<TEntity, TKey>
    where TEntity : class
{
    public IQueryable<TEntity> Query() => dbContext.Set<TEntity>();

    public async Task<TEntity?> GetByIdAsync(TKey id, CancellationToken cancellationToken = default)
        => await dbContext.Set<TEntity>().FindAsync([id], cancellationToken);

    public Task<bool> AnyAsync(Expression<Func<TEntity, bool>> predicate, CancellationToken cancellationToken = default)
        => dbContext.Set<TEntity>().AnyAsync(predicate, cancellationToken);

    public async Task AddAsync(TEntity entity, CancellationToken cancellationToken = default)
        => await dbContext.Set<TEntity>().AddAsync(entity, cancellationToken);

    public void Update(TEntity entity) => dbContext.Set<TEntity>().Update(entity);

    public void Remove(TEntity entity) => dbContext.Set<TEntity>().Remove(entity);
}
