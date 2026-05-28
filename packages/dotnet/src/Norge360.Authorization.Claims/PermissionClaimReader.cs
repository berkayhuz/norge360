// <copyright file="PermissionClaimReader.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;

namespace Norge360.Authorization.Claims;

public static class PermissionClaimReader
{
    private static readonly string[] PermissionClaimTypes = ["permission", "permissions", "scope", "scp"];
    private static readonly string[] RoleClaimTypes = [ClaimTypes.Role, "role", "roles"];
    private static readonly string[] TenantClaimTypes = ["tenant_id", "tenantId", "tenant"];

    public static IReadOnlyCollection<string> ReadPermissions(ClaimsPrincipal? principal) =>
        ReadValues(principal, PermissionClaimTypes);

    public static IReadOnlyCollection<string> ReadRoles(ClaimsPrincipal? principal) =>
        ReadValues(principal, RoleClaimTypes);

    public static bool HasPermission(ClaimsPrincipal? principal, string permission)
    {
        if (principal is null || !HasTenant(principal))
        {
            return false;
        }

        foreach (var claimType in PermissionClaimTypes)
        {
            foreach (var claim in principal.FindAll(claimType))
            {
                if (ContainsPermissionToken(claim.Value, permission))
                {
                    return true;
                }
            }
        }

        return false;
    }

    public static bool HasTenant(ClaimsPrincipal? principal) =>
        TryReadTenantId(principal) is not null;

    private static IReadOnlyCollection<string> ReadValues(ClaimsPrincipal? principal, IEnumerable<string> claimTypes)
    {
        if (principal is null)
        {
            return [];
        }

        var values = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var claimType in claimTypes)
        {
            foreach (var claim in principal.FindAll(claimType))
            {
                AddSplitClaimValues(claim.Value, values);
            }
        }

        return values.Count == 0 ? [] : values.ToArray();
    }

    private static Guid? TryReadTenantId(ClaimsPrincipal? principal)
    {
        if (principal is null)
        {
            return null;
        }

        foreach (var claimType in TenantClaimTypes)
        {
            var value = principal.FindFirst(claimType)?.Value;
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            if (Guid.TryParse(value, out var tenantId) && tenantId != Guid.Empty)
            {
                return tenantId;
            }
        }

        return null;
    }

    private static void AddSplitClaimValues(string? value, HashSet<string> values)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        var span = value.AsSpan();
        var start = 0;
        for (var i = 0; i <= span.Length; i++)
        {
            var isSeparator = i == span.Length || span[i] is ' ' or ',' or ';';
            if (!isSeparator)
            {
                continue;
            }

            var token = span[start..i].Trim();
            if (!token.IsEmpty)
            {
                values.Add(token.ToString());
            }

            start = i + 1;
        }
    }

    private static bool ContainsPermissionToken(string? value, string permission)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var span = value.AsSpan();
        var start = 0;
        for (var i = 0; i <= span.Length; i++)
        {
            var isSeparator = i == span.Length || span[i] is ' ' or ',' or ';';
            if (!isSeparator)
            {
                continue;
            }

            var token = span[start..i].Trim();
            if (!token.IsEmpty)
            {
                if (token.Equals("*".AsSpan(), StringComparison.OrdinalIgnoreCase) ||
                    token.Equals(permission.AsSpan(), StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            start = i + 1;
        }

        return false;
    }
}
