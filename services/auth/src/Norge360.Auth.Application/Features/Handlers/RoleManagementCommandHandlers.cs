// <copyright file="RoleManagementCommandHandlers.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using MediatR;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Application.Security;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed class ListTenantMembersCommandHandler(IUserRepository users)
    : IRequestHandler<ListTenantMembersCommand, IReadOnlyCollection<TenantMemberResponse>>
{
    public async Task<IReadOnlyCollection<TenantMemberResponse>> Handle(ListTenantMembersCommand request, CancellationToken cancellationToken)
    {
        await RoleManagementGuards.EnsureCanReadMembersAsync(users, request.TenantId, request.RequestedByUserId, cancellationToken);
        var memberships = await users.ListMembershipsByTenantAsync(request.TenantId, cancellationToken);
        return memberships
            .Where(x => x.User is not null)
            .Select(x => RoleManagementGuards.ToResponse(x.User!, x))
            .ToArray();
    }
}

public sealed class ListRoleCatalogCommandHandler(IUserRepository users)
    : IRequestHandler<ListRoleCatalogCommand, IReadOnlyCollection<RoleCatalogResponse>>
{
    public async Task<IReadOnlyCollection<RoleCatalogResponse>> Handle(ListRoleCatalogCommand request, CancellationToken cancellationToken)
    {
        await RoleManagementGuards.EnsureCanReadMembersAsync(users, request.TenantId, request.RequestedByUserId, cancellationToken);
        return AuthorizationCatalog.RolesCatalog
            .Select(role => new RoleCatalogResponse(role.Name, role.Rank, role.IsProtected, role.Permissions))
            .ToArray();
    }
}

public sealed class UpdateTenantMemberRolesCommandHandler(
    IUserRepository users,
    IAuthAuditTrail auditTrail,
    IAuthUnitOfWork unitOfWork,
    IUserTokenStateValidator userTokenStateValidator)
    : IRequestHandler<UpdateTenantMemberRolesCommand, TenantMemberResponse>
{
    public async Task<TenantMemberResponse> Handle(UpdateTenantMemberRolesCommand request, CancellationToken cancellationToken)
    {
        var actor = await RoleManagementGuards.EnsureCanManageRolesAsync(users, request.TenantId, request.RequestedByUserId, cancellationToken);
        var actorMembership = await users.GetMembershipAsync(request.TenantId, actor.Id, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Tenant membership is required.", (int)HttpStatusCode.Forbidden, errorCode: "membership_forbidden");
        var target = await users.GetActiveByIdAsync(request.TenantId, request.TargetUserId, cancellationToken);
        var targetMembership = await users.GetMembershipAsync(request.TenantId, request.TargetUserId, cancellationToken);
        if (target is null)
        {
            await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.authorization.denied", "membership_not_found", actor.Id, null, null, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
            throw new AuthApplicationException("Member not found", "Tenant member could not be found.", (int)HttpStatusCode.NotFound, errorCode: "member_not_found");
        }
        if (targetMembership is null)
        {
            await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.authorization.denied", "membership_not_found", actor.Id, null, null, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
            throw new AuthApplicationException("Member not found", "Tenant member could not be found.", (int)HttpStatusCode.NotFound, errorCode: "member_not_found");
        }

        var normalizedRoles = request.Roles
            .Where(role => !string.IsNullOrWhiteSpace(role))
            .Select(role => role.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (normalizedRoles.Length == 0 || normalizedRoles.Any(role => !AuthorizationCatalog.IsKnownRole(role)))
        {
            throw new AuthApplicationException("Invalid roles", "Only catalog roles can be assigned.", (int)HttpStatusCode.BadRequest, errorCode: "invalid_role_assignment");
        }

        var actorIsOwner = actorMembership.GetRoles().Contains(AuthorizationCatalog.Roles.TenantOwner, StringComparer.OrdinalIgnoreCase);
        var actorRank = AuthorizationCatalog.HighestRoleRank(actorMembership.GetRoles());
        var targetRank = AuthorizationCatalog.HighestRoleRank(targetMembership.GetRoles());
        var requestedRank = AuthorizationCatalog.HighestRoleRank(normalizedRoles);

        if (!actorIsOwner && (requestedRank >= actorRank || targetRank >= actorRank))
        {
            await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.authorization.denied", "role_hierarchy", actor.Id, null, target.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
            throw new AuthApplicationException("Forbidden", "Role assignment exceeds the administrator delegation boundary.", (int)HttpStatusCode.Forbidden, errorCode: "role_hierarchy_forbidden");
        }

        var removesOwner = targetMembership.GetRoles().Contains(AuthorizationCatalog.Roles.TenantOwner, StringComparer.OrdinalIgnoreCase) &&
                           !normalizedRoles.Contains(AuthorizationCatalog.Roles.TenantOwner, StringComparer.OrdinalIgnoreCase);
        if (removesOwner)
        {
            var ownerCount = await users.CountActiveUsersInRoleAsync(request.TenantId, AuthorizationCatalog.Roles.TenantOwner, cancellationToken);
            if (ownerCount <= 1)
            {
                await auditTrail.WriteAsync(new AuthAuditRecord(request.TenantId, "auth.authorization.denied", "last_owner", actor.Id, null, target.Email, request.IpAddress, request.UserAgent, request.CorrelationId, request.TraceId), cancellationToken);
                throw new AuthApplicationException("Forbidden", "The last tenant owner cannot be demoted.", (int)HttpStatusCode.Conflict, errorCode: "last_owner_protected");
            }
        }

        var oldRoles = targetMembership.GetRoles();
        targetMembership.Roles = AuthorizationCatalog.Serialize(normalizedRoles);
        targetMembership.Permissions = AuthorizationCatalog.Serialize(AuthorizationCatalog.ResolvePermissions(normalizedRoles));
        targetMembership.LastRoleChangeAt = DateTime.UtcNow;
        targetMembership.LastRoleChangedByUserId = actor.Id;
        targetMembership.UpdatedAt = DateTime.UtcNow;
        targetMembership.UpdatedBy = actor.Id.ToString("N");
        target.SecurityStamp = Guid.NewGuid().ToString("N");
        target.TokenVersion++;
        target.UpdatedAt = DateTime.UtcNow;
        target.UpdatedBy = actor.Id.ToString("N");

        await auditTrail.WriteAsync(new AuthAuditRecord(
            request.TenantId,
            "auth.roles.changed",
            "success",
            actor.Id,
            null,
            target.Email,
            AuthenticationNormalization.CleanOrNull(request.IpAddress),
            AuthenticationNormalization.CleanOrNull(request.UserAgent),
            request.CorrelationId,
            request.TraceId,
            $"targetUserId={target.Id};oldRoles={string.Join('|', oldRoles)};newRoles={string.Join('|', normalizedRoles)}"),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);
        userTokenStateValidator.Evict(request.TenantId, target.Id);
        return RoleManagementGuards.ToResponse(target, targetMembership);
    }
}

internal static class RoleManagementGuards
{
    public static async Task<User> EnsureCanReadMembersAsync(IUserRepository users, Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.GetActiveByIdAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Tenant membership is required.", (int)HttpStatusCode.Forbidden, errorCode: "membership_forbidden");
        var membership = await users.GetMembershipAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Tenant membership is required.", (int)HttpStatusCode.Forbidden, errorCode: "membership_forbidden");

        if (!HasPermission(membership, AuthorizationCatalog.Permissions.RolesRead) &&
            !HasPermission(membership, AuthorizationCatalog.Permissions.RolesManage) &&
            !HasPermission(membership, AuthorizationCatalog.Permissions.UsersManage))
        {
            throw new AuthApplicationException("Forbidden", "Tenant member visibility requires role or user management permission.", (int)HttpStatusCode.Forbidden, errorCode: "roles_read_forbidden");
        }

        return user;
    }

    public static async Task<User> EnsureCanManageRolesAsync(IUserRepository users, Guid tenantId, Guid userId, CancellationToken cancellationToken)
    {
        var user = await users.GetActiveByIdAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Tenant membership is required.", (int)HttpStatusCode.Forbidden, errorCode: "membership_forbidden");
        var membership = await users.GetMembershipAsync(tenantId, userId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Tenant membership is required.", (int)HttpStatusCode.Forbidden, errorCode: "membership_forbidden");

        if (!HasPermission(membership, AuthorizationCatalog.Permissions.RolesManage))
        {
            throw new AuthApplicationException("Forbidden", "Role management permission is required.", (int)HttpStatusCode.Forbidden, errorCode: "roles_manage_forbidden");
        }

        return user;
    }

    public static TenantMemberResponse ToResponse(User user, UserTenantMembership membership) =>
        new(
            membership.TenantId,
            user.Id,
            user.UserName,
            user.Email ?? string.Empty,
            user.FirstName,
            user.LastName,
            user.IsActive,
            membership.GetRoles(),
            membership.GetPermissions(),
            user.CreatedAt,
            user.LastLoginAt);

    private static bool HasPermission(UserTenantMembership membership, string permission) =>
        membership.GetPermissions().Contains(AuthorizationCatalog.WildcardPermission, StringComparer.OrdinalIgnoreCase) ||
        membership.GetPermissions().Contains(permission, StringComparer.OrdinalIgnoreCase);
}
