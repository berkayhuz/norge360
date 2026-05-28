// <copyright file="IUserRepository.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Abstractions;

public interface IUserRepository
{
    Task<User?> FindByTenantAndIdentityAsync(Guid tenantId, string normalizedIdentity, CancellationToken cancellationToken);
    Task<User?> FindByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken);
    Task<LoginScopeResolution?> ResolveLoginScopeByIdentityAsync(string normalizedIdentity, CancellationToken cancellationToken);
    Task<User?> GetActiveByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task<User?> GetByIdAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task<User?> GetByIdIncludingInactiveAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task<ActiveUserTokenState?> GetActiveTokenStateAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task<UserTenantMembership?> GetMembershipAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task<IReadOnlyCollection<UserTenantMembershipSnapshot>> ListMembershipsByUserAsync(Guid userId, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyCollection<UserTenantMembershipSnapshot>>(Array.Empty<UserTenantMembershipSnapshot>());
    Task<IReadOnlyCollection<UserTenantMembership>> ListMembershipsByTenantAsync(Guid tenantId, CancellationToken cancellationToken);
    Task<IReadOnlyCollection<User>> ListByTenantAsync(Guid tenantId, CancellationToken cancellationToken);
    Task<int> CountActiveUsersInRoleAsync(Guid tenantId, string role, CancellationToken cancellationToken);
    Task<bool> ExistsByUserNameAsync(Guid tenantId, string normalizedUserName, CancellationToken cancellationToken);
    Task<bool> ExistsByEmailAsync(Guid tenantId, string normalizedEmail, CancellationToken cancellationToken);
    Task<bool> ExistsByEmailAsync(string normalizedEmail, CancellationToken cancellationToken);
    Task<bool> AnyActiveUserInTenantAsync(Guid tenantId, CancellationToken cancellationToken);
    Task<bool> IsFirstActiveUserInTenantAsync(Guid tenantId, Guid userId, CancellationToken cancellationToken);
    Task RecordFailedLoginAsync(Guid tenantId, Guid userId, int maxFailedAttempts, DateTime lockoutEndAt, DateTime utcNow, CancellationToken cancellationToken);
    Task AddAsync(User user, CancellationToken cancellationToken);
    Task AddMembershipAsync(UserTenantMembership membership, CancellationToken cancellationToken);
}

public sealed record LoginScopeResolution(
    Guid TenantId,
    Guid UserId);

public sealed record ActiveUserTokenState(int TokenVersion);

public sealed record UserTenantMembershipSnapshot(
    Guid TenantId,
    string TenantName,
    string TenantSlug,
    Guid UserId,
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    bool IsActive,
    IReadOnlyCollection<string> Roles,
    IReadOnlyCollection<string> Permissions);
