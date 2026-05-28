// <copyright file="UserRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Microsoft.EntityFrameworkCore;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Domain.Entities;
using Norge360.Auth.Infrastructure.Persistence;

namespace Norge360.Auth.Infrastructure.Services;

public sealed class UserRepository(AuthDbContext dbContext) : IUserRepository
{
    public Task<User?> FindByTenantAndIdentityAsync(Guid tenantId, string normalizedIdentity, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive)
            .Select(x => x.User!)
            .SingleOrDefaultAsync(
                x => !x.IsDeleted &&
                     x.IsActive &&
                     (x.NormalizedEmail == normalizedIdentity || x.NormalizedUserName == normalizedIdentity),
                cancellationToken);

    public Task<User?> FindByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken) =>
        dbContext.Users.SingleOrDefaultAsync(
            x => !x.IsDeleted &&
                 x.IsActive &&
                 (x.NormalizedEmail == normalizedIdentity || x.NormalizedUserName == normalizedIdentity),
            cancellationToken);

    public async Task<LoginScopeResolution?> ResolveLoginScopeByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken)
    {
        var membership = await dbContext.UserTenantMemberships
            .AsNoTracking()
            .Where(m =>
                !m.IsDeleted &&
                m.IsActive &&
                m.User != null &&
                !m.User.IsDeleted &&
                m.User.IsActive &&
                (m.User.NormalizedEmail == normalizedIdentity || m.User.NormalizedUserName == normalizedIdentity))
            .Join(
                dbContext.Tenants.AsNoTracking().Where(t => t.IsActive),
                membership => membership.TenantId,
                tenant => tenant.Id,
                (membership, _) => membership)
            .OrderBy(m => m.CreatedAt)
            .ThenBy(m => m.Id)
            .Select(m => new LoginScopeResolution(m.TenantId, m.UserId))
            .FirstOrDefaultAsync(cancellationToken);

        return membership;
    }

    public Task<User?> GetActiveByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenantId && x.UserId == userId && !x.IsDeleted && x.IsActive)
            .Select(x => x.User!)
            .SingleOrDefaultAsync(x => x.Id == userId && !x.IsDeleted && x.IsActive, cancellationToken);

    public Task<User?> GetByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
        GetActiveByIdAsync(tenantId, userId, cancellationToken);

    public Task<User?> GetByIdIncludingInactiveAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenantId && x.UserId == userId && !x.IsDeleted)
            .Select(x => x.User!)
            .SingleOrDefaultAsync(x => x.Id == userId && !x.IsDeleted, cancellationToken);

    public Task<ActiveUserTokenState?> GetActiveTokenStateAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .AsNoTracking()
            .Where(x => x.TenantId == tenantId && x.UserId == userId && !x.IsDeleted && x.IsActive)
            .Select(x => x.User!)
            .Where(x => x.Id == userId && !x.IsDeleted && x.IsActive)
            .Select(x => new ActiveUserTokenState(x.TokenVersion))
            .SingleOrDefaultAsync(cancellationToken);

    public Task<UserTenantMembership?> GetMembershipAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .SingleOrDefaultAsync(
                x => x.TenantId == tenantId &&
                     x.UserId == userId &&
                     !x.IsDeleted &&
                     x.IsActive,
                cancellationToken);

    public async Task<IReadOnlyCollection<UserTenantMembershipSnapshot>> ListMembershipsByUserAsync(Guid userId, CancellationToken cancellationToken)
    {
        var rows = await dbContext.UserTenantMemberships
            .AsNoTracking()
            .Where(x => x.UserId == userId && !x.IsDeleted && x.IsActive)
            .Join(
                dbContext.Tenants.AsNoTracking().Where(x => x.IsActive),
                membership => membership.TenantId,
                tenant => tenant.Id,
                (membership, tenant) => new { Membership = membership, Tenant = tenant })
            .OrderBy(x => x.Tenant.Name)
            .ToArrayAsync(cancellationToken);

        return rows
            .Select(x => new UserTenantMembershipSnapshot(
                x.Tenant.Id,
                x.Tenant.Name,
                x.Tenant.Slug,
                x.Membership.UserId,
                x.Membership.CreatedAt,
                x.Membership.UpdatedAt,
                x.Membership.IsActive,
                x.Membership.GetRoles(),
                x.Membership.GetPermissions()))
            .ToArray();
    }

    public async Task<IReadOnlyCollection<UserTenantMembership>> ListMembershipsByTenantAsync(Guid tenantId, CancellationToken cancellationToken) =>
        await dbContext.UserTenantMemberships
            .AsNoTracking()
            .Include(x => x.User)
            .Where(x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive && !x.User!.IsDeleted)
            .OrderBy(x => x.User!.UserName)
            .ToArrayAsync(cancellationToken);

    public async Task<IReadOnlyCollection<User>> ListByTenantAsync(Guid tenantId, CancellationToken cancellationToken) =>
        await dbContext.UserTenantMemberships
            .AsNoTracking()
            .Include(x => x.User)
            .Where(x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive && !x.User!.IsDeleted)
            .OrderBy(x => x.User!.UserName)
            .Select(x => x.User!)
            .ToArrayAsync(cancellationToken);

    public Task<int> CountActiveUsersInRoleAsync(Guid tenantId, string role, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships.CountAsync(
            x => x.TenantId == tenantId &&
                 !x.IsDeleted &&
                 x.IsActive &&
                 ("," + x.Roles + ",").Contains("," + role + ","),
            cancellationToken);

    public Task<bool> ExistsByUserNameAsync(Guid tenantId, string normalizedUserName, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive)
            .AnyAsync(x => !x.User!.IsDeleted && x.User.NormalizedUserName == normalizedUserName, cancellationToken);

    public Task<bool> ExistsByEmailAsync(Guid tenantId, string normalizedEmail, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive)
            .AnyAsync(x => !x.User!.IsDeleted && x.User.NormalizedEmail == normalizedEmail, cancellationToken);

    public Task<bool> ExistsByEmailAsync(string normalizedEmail, CancellationToken cancellationToken) =>
        dbContext.Users
            .AnyAsync(x => !x.IsDeleted && x.NormalizedEmail == normalizedEmail, cancellationToken);

    public Task<bool> AnyActiveUserInTenantAsync(Guid tenantId, CancellationToken cancellationToken) =>
        dbContext.UserTenantMemberships.AnyAsync(
            x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive,
            cancellationToken);

    public async Task<bool> IsFirstActiveUserInTenantAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        var firstUserId = await dbContext.UserTenantMemberships
            .Where(x => x.TenantId == tenantId && !x.IsDeleted && x.IsActive)
            .OrderBy(x => x.CreatedAt)
            .ThenBy(x => x.Id)
            .Select(x => x.UserId)
            .FirstOrDefaultAsync(cancellationToken);

        return firstUserId == userId;
    }

    public Task RecordFailedLoginAsync(
        Guid tenantId,
        Guid userId,
        int maxFailedAttempts,
        DateTime lockoutEndAt,
        DateTime utcNow,
        CancellationToken cancellationToken) =>
        dbContext.Users
            .Where(x => x.Id == userId &&
                        !x.IsDeleted &&
                        dbContext.UserTenantMemberships.Any(m => m.TenantId == tenantId && m.UserId == userId && !m.IsDeleted && m.IsActive))
            .ExecuteUpdateAsync(updates => updates
                .SetProperty(x => x.AccessFailedCount, x => x.AccessFailedCount + 1)
                .SetProperty(x => x.IsLocked, x => x.AccessFailedCount + 1 >= maxFailedAttempts)
                .SetProperty(
                    x => x.LockoutEndAt,
                    x => x.AccessFailedCount + 1 >= maxFailedAttempts ? (DateTime?)lockoutEndAt : x.LockoutEndAt)
                .SetProperty(x => x.UpdatedAt, utcNow), cancellationToken);

    public async Task AddAsync(User user, CancellationToken cancellationToken) =>
        await dbContext.Users.AddAsync(user, cancellationToken);

    public async Task AddMembershipAsync(UserTenantMembership membership, CancellationToken cancellationToken) =>
        await dbContext.UserTenantMemberships.AddAsync(membership, cancellationToken);
}
