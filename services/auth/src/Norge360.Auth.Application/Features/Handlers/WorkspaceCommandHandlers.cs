// <copyright file="WorkspaceCommandHandlers.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Net;
using System.Text.RegularExpressions;
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Norge360.Auth.Application.Abstractions;
using Norge360.Auth.Application.Diagnostics;
using Norge360.Auth.Application.Exceptions;
using Norge360.Auth.Application.Features.Commands;
using Norge360.Auth.Application.Helpers;
using Norge360.Auth.Application.Options;
using Norge360.Auth.Application.Records;
using Norge360.Auth.Application.Security;
using Norge360.Auth.Contracts.IntegrationEvents;
using Norge360.Auth.Contracts.Internal;
using Norge360.Auth.Contracts.Responses;
using Norge360.Auth.Domain.Entities;
using Norge360.Clock;
using Norge360.Localization;

namespace Norge360.Auth.Application.Features.Handlers;

public sealed partial class CreateWorkspaceCommandHandler(
    ITenantRepository tenantRepository,
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IIntegrationEventOutbox integrationEventOutbox,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IAuthSessionService authSessionService,
    IUserSessionStateValidator userSessionStateValidator,
    IClock clock,
    IOptions<AuthorizationOptions> authorizationOptions)
    : IRequestHandler<CreateWorkspaceCommand, AuthenticationTokenResponse>
{
    private const int MaxWorkspacesPerUser = 5;

    public async Task<AuthenticationTokenResponse> Handle(CreateWorkspaceCommand request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Trim().Length < 2 || request.Name.Trim().Length > 200)
        {
            throw new AuthApplicationException("Invalid workspace name", "Workspace name must be between 2 and 200 characters.", (int)HttpStatusCode.BadRequest, errorCode: "invalid_workspace_name");
        }

        var actor = await userRepository.GetActiveByIdAsync(request.CurrentTenantId, request.UserId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "Authenticated user membership is required.", (int)HttpStatusCode.Forbidden, errorCode: "membership_forbidden");

        var existingWorkspaces = await userRepository.ListMembershipsByUserAsync(actor.Id, cancellationToken);
        if (existingWorkspaces.Count >= MaxWorkspacesPerUser)
        {
            throw new AuthApplicationException("Workspace limit reached", "A user can create up to 5 workspaces.", (int)HttpStatusCode.Conflict, errorCode: "workspace_limit_reached");
        }

        var utcNow = clock.UtcDateTime;
        var culture = Norge360Cultures.NormalizeOrDefault(request.Culture);
        var tenant = new Tenant
        {
            Id = Guid.NewGuid(),
            Name = request.Name.Trim(),
            Slug = CreateUniqueSlug(request.Name),
            IsActive = true,
            CreatedAt = utcNow,
            CreatedBy = actor.Id.ToString("N")
        };

        var authorization = authorizationOptions.Value;
        var roles = authorization.BootstrapFirstUserAsTenantOwner
            ? authorization.BootstrapFirstUserRoles
            : authorization.DefaultRoles;
        var permissions = authorization.BootstrapFirstUserAsTenantOwner
            ? authorization.BootstrapFirstUserPermissions
            : authorization.DefaultPermissions;

        var membership = new UserTenantMembership
        {
            TenantId = tenant.Id,
            UserId = actor.Id,
            Roles = Serialize(roles),
            Permissions = Serialize(permissions),
            CreatedAt = utcNow,
            CreatedBy = actor.Id.ToString("N")
        };

        await tenantRepository.AddAsync(tenant, cancellationToken);
        await userRepository.AddMembershipAsync(membership, cancellationToken);

        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                tenant.Id,
                "auth.workspace.created",
                "success",
                actor.Id,
                null,
                actor.Email,
                AuthenticationNormalization.CleanOrNull(request.IpAddress),
                AuthenticationNormalization.CleanOrNull(request.UserAgent),
                request.CorrelationId,
                request.TraceId),
            cancellationToken);

        await integrationEventOutbox.AddAsync(
            Guid.NewGuid(),
            UserRegisteredV1.EventName,
            UserRegisteredV1.EventVersion,
            UserRegisteredV1.RoutingKey,
            "Norge360.Auth",
            new UserRegisteredV1(actor.Id, tenant.Id, actor.UserName, actor.Email ?? string.Empty, actor.FirstName, actor.LastName, utcNow, culture),
            request.CorrelationId,
            request.TraceId,
            utcNow,
            cancellationToken);

        return await SaveAndIssueAsync(actor, tenant, membership, request.IpAddress, request.UserAgent, cancellationToken);
    }

    private async Task<AuthenticationTokenResponse> SaveAndIssueAsync(
        User user,
        Tenant tenant,
        UserTenantMembership membership,
        string? ipAddress,
        string? userAgent,
        CancellationToken cancellationToken)
    {
        var refreshToken = refreshTokenService.Generate(isPersistent: true);
        var utcNow = clock.UtcDateTime;
        var session = new UserSession
        {
            TenantId = tenant.Id,
            UserId = user.Id,
            IsPersistent = true,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = refreshToken.Hash,
            RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc,
            CreatedAt = utcNow,
            LastSeenAt = utcNow,
            LastRefreshedAt = utcNow,
            IpAddress = AuthenticationNormalization.CleanOrNull(ipAddress),
            UserAgent = AuthenticationNormalization.CleanOrNull(userAgent),
            CreatedBy = user.Id.ToString("N")
        };

        await userSessionRepository.AddAsync(session, cancellationToken);
        var revokedSessionIds = await authSessionService.EnforceSessionLimitsAsync(tenant.Id, user.Id, session.Id, cancellationToken);

        try
        {
            await unitOfWork.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw new AuthApplicationException("Workspace could not be created", "The workspace request could not be completed.", (int)HttpStatusCode.Conflict, errorCode: "workspace_create_conflict");
        }

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(tenant.Id, sessionId);
        }

        AuthMetrics.AuthSucceeded.Add(1, new KeyValuePair<string, object?>("flow", "workspace"));
        var accessToken = accessTokenFactory.Create(user.Id, user.UserName, user.Email ?? string.Empty, user.TokenVersion, membership.GetRoles(), membership.GetPermissions(), tenant.Id, session.Id);
        return new AuthenticationTokenResponse(accessToken.Token, accessToken.ExpiresAtUtc, refreshToken.Token, refreshToken.ExpiresAtUtc, tenant.Id, user.Id, user.UserName, user.Email ?? string.Empty, session.Id, IsPersistent: true);
    }

    private static string Serialize(IEnumerable<string> values) =>
        string.Join(',', values.Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim()).Distinct(StringComparer.OrdinalIgnoreCase));

    private static string CreateUniqueSlug(string tenantName)
    {
        var normalized = SlugUnsafeCharacters().Replace(tenantName.Trim().ToLowerInvariant(), "-").Trim('-');
        if (string.IsNullOrWhiteSpace(normalized))
        {
            normalized = "workspace";
        }

        if (normalized.Length > 70)
        {
            normalized = normalized[..70].Trim('-');
        }

        return $"{normalized}-{Guid.NewGuid():N}"[..Math.Min(normalized.Length + 9, 80)];
    }

    [GeneratedRegex("[^a-z0-9]+", RegexOptions.CultureInvariant)]
    private static partial Regex SlugUnsafeCharacters();
}

public sealed class DeleteWorkspaceCommandHandler(
    ITenantRepository tenantRepository,
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IUserTokenStateValidator userTokenStateValidator,
    IUserSessionStateValidator userSessionStateValidator,
    IClock clock)
    : IRequestHandler<DeleteWorkspaceCommand>
{
    public async Task Handle(DeleteWorkspaceCommand request, CancellationToken cancellationToken)
    {
        if (request.TargetTenantId == request.CurrentTenantId)
        {
            throw new AuthApplicationException("Workspace cannot be deleted", "Switch to another workspace before deleting the active workspace.", (int)HttpStatusCode.Conflict, errorCode: "active_workspace_delete_forbidden");
        }

        var tenant = await tenantRepository.GetByIdAsync(request.TargetTenantId, cancellationToken)
            ?? throw new AuthApplicationException("Workspace not found", "The selected workspace could not be found.", (int)HttpStatusCode.NotFound, errorCode: "workspace_not_found");

        var actorMembership = await userRepository.GetMembershipAsync(request.TargetTenantId, request.UserId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "You are not allowed to delete this workspace.", (int)HttpStatusCode.Forbidden, errorCode: "workspace_delete_forbidden");

        if (!CanDeleteWorkspace(actorMembership))
        {
            throw new AuthApplicationException("Forbidden", "You are not allowed to delete this workspace.", (int)HttpStatusCode.Forbidden, errorCode: "workspace_delete_forbidden");
        }

        var memberships = await userRepository.ListMembershipsByUserAsync(request.UserId, cancellationToken);
        if (memberships.Count <= 1)
        {
            throw new AuthApplicationException("Workspace cannot be deleted", "At least one workspace must remain available.", (int)HttpStatusCode.Conflict, errorCode: "last_workspace_delete_forbidden");
        }

        var utcNow = clock.UtcDateTime;
        var affectedMembers = await userRepository.ListMembershipsByTenantAsync(request.TargetTenantId, cancellationToken);
        var affectedUserIds = affectedMembers
            .Select(member => member.UserId)
            .Distinct()
            .ToArray();

        await tenantRepository.DeactivateAsync(tenant, utcNow, request.UserId, cancellationToken);

        var revokedSessionIds = new List<Guid>();
        foreach (var affectedUserId in affectedUserIds)
        {
            var revokedForUser = await userSessionRepository.RevokeAllAsync(
                request.TargetTenantId,
                affectedUserId,
                utcNow,
                "tenant_deactivated",
                excludedSessionId: null,
                cancellationToken);

            revokedSessionIds.AddRange(revokedForUser);
            userTokenStateValidator.Evict(request.TargetTenantId, affectedUserId);
        }

        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                request.TargetTenantId,
                "auth.workspace.deleted",
                "success",
                request.UserId,
                null,
                null,
                AuthenticationNormalization.CleanOrNull(request.IpAddress),
                AuthenticationNormalization.CleanOrNull(request.UserAgent),
                request.CorrelationId,
                request.TraceId),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(request.TargetTenantId, sessionId);
        }
    }

    private static bool CanDeleteWorkspace(UserTenantMembership membership) =>
        membership.GetPermissions().Contains(AuthorizationCatalog.WildcardPermission, StringComparer.OrdinalIgnoreCase) ||
        membership.GetRoles().Contains(AuthorizationCatalog.Roles.TenantOwner, StringComparer.OrdinalIgnoreCase);
}

public sealed class SwitchWorkspaceCommandHandler(
    ITenantRepository tenantRepository,
    IUserRepository userRepository,
    IUserSessionRepository userSessionRepository,
    IAuthUnitOfWork unitOfWork,
    IAuthAuditTrail auditTrail,
    IAccessTokenFactory accessTokenFactory,
    IRefreshTokenService refreshTokenService,
    IAuthSessionService authSessionService,
    IUserSessionStateValidator userSessionStateValidator,
    IClock clock)
    : IRequestHandler<SwitchWorkspaceCommand, AuthenticationTokenResponse>
{
    public async Task<AuthenticationTokenResponse> Handle(SwitchWorkspaceCommand request, CancellationToken cancellationToken)
    {
        var tenant = await tenantRepository.GetByIdAsync(request.TargetTenantId, cancellationToken)
            ?? throw new AuthApplicationException("Workspace not found", "The selected workspace could not be found.", (int)HttpStatusCode.NotFound, errorCode: "workspace_not_found");
        if (!tenant.IsActive)
        {
            throw new AuthApplicationException("Workspace not found", "The selected workspace could not be found.", (int)HttpStatusCode.NotFound, errorCode: "workspace_not_found");
        }

        var user = await userRepository.GetActiveByIdAsync(request.TargetTenantId, request.UserId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "You are not a member of the selected workspace.", (int)HttpStatusCode.Forbidden, errorCode: "workspace_membership_forbidden");
        if (!user.IsActive)
        {
            throw new AuthApplicationException("Forbidden", "You are not a member of the selected workspace.", (int)HttpStatusCode.Forbidden, errorCode: "workspace_membership_forbidden");
        }

        var membership = await userRepository.GetMembershipAsync(request.TargetTenantId, request.UserId, cancellationToken)
            ?? throw new AuthApplicationException("Forbidden", "You are not a member of the selected workspace.", (int)HttpStatusCode.Forbidden, errorCode: "workspace_membership_forbidden");
        if (!membership.IsActive)
        {
            throw new AuthApplicationException("Forbidden", "You are not a member of the selected workspace.", (int)HttpStatusCode.Forbidden, errorCode: "workspace_membership_forbidden");
        }

        var refreshToken = refreshTokenService.Generate(isPersistent: true);
        var utcNow = clock.UtcDateTime;
        var session = new UserSession
        {
            TenantId = tenant.Id,
            UserId = user.Id,
            IsPersistent = true,
            RefreshTokenFamilyId = Guid.NewGuid(),
            RefreshTokenHash = refreshToken.Hash,
            RefreshTokenExpiresAt = refreshToken.ExpiresAtUtc,
            CreatedAt = utcNow,
            LastSeenAt = utcNow,
            LastRefreshedAt = utcNow,
            IpAddress = AuthenticationNormalization.CleanOrNull(request.IpAddress),
            UserAgent = AuthenticationNormalization.CleanOrNull(request.UserAgent),
            CreatedBy = user.Id.ToString("N")
        };

        await userSessionRepository.AddAsync(session, cancellationToken);
        var revokedSessionIds = await authSessionService.EnforceSessionLimitsAsync(tenant.Id, user.Id, session.Id, cancellationToken);
        await auditTrail.WriteAsync(
            new AuthAuditRecord(
                tenant.Id,
                "auth.workspace.switched",
                "success",
                user.Id,
                session.Id,
                user.Email,
                session.IpAddress,
                session.UserAgent,
                request.CorrelationId,
                request.TraceId,
                $"fromTenantId={request.CurrentTenantId}"),
            cancellationToken);

        await unitOfWork.SaveChangesAsync(cancellationToken);

        foreach (var sessionId in revokedSessionIds)
        {
            userSessionStateValidator.Evict(tenant.Id, sessionId);
        }

        var accessToken = accessTokenFactory.Create(user.Id, user.UserName, user.Email ?? string.Empty, user.TokenVersion, membership.GetRoles(), membership.GetPermissions(), tenant.Id, session.Id);
        return new AuthenticationTokenResponse(accessToken.Token, accessToken.ExpiresAtUtc, refreshToken.Token, refreshToken.ExpiresAtUtc, tenant.Id, user.Id, user.UserName, user.Email ?? string.Empty, session.Id, IsPersistent: true);
    }
}

public sealed class ListUserWorkspaceMembershipsCommandHandler(IUserRepository users)
    : IRequestHandler<ListUserWorkspaceMembershipsCommand, IReadOnlyCollection<InternalOrganizationMembershipSummaryResponse>>
{
    public async Task<IReadOnlyCollection<InternalOrganizationMembershipSummaryResponse>> Handle(ListUserWorkspaceMembershipsCommand request, CancellationToken cancellationToken)
    {
        var memberships = await users.ListMembershipsByUserAsync(request.UserId, cancellationToken);
        return memberships
            .Select(x => new InternalOrganizationMembershipSummaryResponse(
                x.TenantId,
                x.TenantId,
                x.TenantName,
                x.TenantSlug,
                x.IsActive ? "Active" : "Inactive",
                x.TenantId == request.TenantId,
                new DateTimeOffset(x.CreatedAt, TimeSpan.Zero),
                x.UpdatedAt.HasValue ? new DateTimeOffset(x.UpdatedAt.Value, TimeSpan.Zero) : null,
                x.Roles))
            .ToArray();
    }
}

public sealed class GetUserWorkspacePermissionsCommandHandler(IUserRepository users)
    : IRequestHandler<GetUserWorkspacePermissionsCommand, InternalPermissionOverviewResponse>
{
    public async Task<InternalPermissionOverviewResponse> Handle(GetUserWorkspacePermissionsCommand request, CancellationToken cancellationToken)
    {
        var organizationId = request.OrganizationId ?? request.TenantId;
        if (organizationId != request.TenantId)
        {
            return new InternalPermissionOverviewResponse(organizationId, DateTimeOffset.UtcNow, true, [], []);
        }

        var membership = await users.GetMembershipAsync(request.TenantId, request.UserId, cancellationToken);
        if (membership is null)
        {
            return new InternalPermissionOverviewResponse(organizationId, DateTimeOffset.UtcNow, true, [], []);
        }

        var permissions = membership.GetPermissions();
        return new InternalPermissionOverviewResponse(
            organizationId,
            DateTimeOffset.UtcNow,
            false,
            membership.GetRoles(),
            [new InternalPermissionGroupResponse("Workspace", permissions)]);
    }
}
