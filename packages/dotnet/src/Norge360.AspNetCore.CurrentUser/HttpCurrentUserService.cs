// <copyright file="HttpCurrentUserService.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Norge360.Authorization.Claims;
using Norge360.CurrentUser;
using Norge360.Tenancy;

namespace Norge360.AspNetCore.CurrentUser;

public sealed class HttpCurrentUserService(IHttpContextAccessor httpContextAccessor) : ICurrentUserService, ITenantContext, ITenantProvider
{
    private ClaimsPrincipal? Principal => httpContextAccessor.HttpContext?.User;
    private ClaimsPrincipal? _cachedPrincipal;
    private Guid _cachedUserId;
    private Guid _cachedTenantId;
    private bool _isUserIdCached;
    private bool _isTenantIdCached;

    public Guid UserId
    {
        get
        {
            EnsureClaimCacheForCurrentPrincipal();
            if (_isUserIdCached)
            {
                return _cachedUserId;
            }

            _cachedUserId = ReadGuid(Principal, ClaimTypes.NameIdentifier, "sub");
            _isUserIdCached = true;
            return _cachedUserId;
        }
    }

    public Guid TenantId
    {
        get
        {
            EnsureClaimCacheForCurrentPrincipal();
            if (_isTenantIdCached)
            {
                return _cachedTenantId;
            }

            _cachedTenantId = ReadGuid(Principal, "tenant_id", "tenantId", "tenant");
            _isTenantIdCached = true;
            return _cachedTenantId;
        }
    }

    Guid? ITenantContext.TenantId => TenantId == Guid.Empty ? null : TenantId;

    Guid? ITenantProvider.TenantId => TenantId == Guid.Empty ? null : TenantId;

    public bool IsAuthenticated => Principal?.Identity?.IsAuthenticated == true && UserId != Guid.Empty;

    public string? UserName =>
        Principal?.FindFirst(ClaimTypes.Name)?.Value ??
        Principal?.FindFirst("name")?.Value ??
        Principal?.Identity?.Name;

    public string? Email =>
        Principal?.FindFirst(ClaimTypes.Email)?.Value ??
        Principal?.FindFirst("email")?.Value;

    public IReadOnlyCollection<string> Roles => PermissionClaimReader.ReadRoles(Principal);

    public IReadOnlyCollection<string> Permissions => PermissionClaimReader.ReadPermissions(Principal);

    public bool IsInRole(string role) => Principal?.IsInRole(role) == true || Roles.Contains(role, StringComparer.OrdinalIgnoreCase);

    public bool HasPermission(string permission) => PermissionClaimReader.HasPermission(Principal, permission);

    private void EnsureClaimCacheForCurrentPrincipal()
    {
        var principal = Principal;
        if (ReferenceEquals(principal, _cachedPrincipal))
        {
            return;
        }

        _cachedPrincipal = principal;
        _cachedUserId = Guid.Empty;
        _cachedTenantId = Guid.Empty;
        _isUserIdCached = false;
        _isTenantIdCached = false;
    }

    private static Guid ReadGuid(ClaimsPrincipal? principal, params string[] claimTypes)
    {
        var value = claimTypes
            .Select(type => principal?.FindFirst(type)?.Value)
            .FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate));

        return Guid.TryParse(value, out var parsed) ? parsed : Guid.Empty;
    }

}
