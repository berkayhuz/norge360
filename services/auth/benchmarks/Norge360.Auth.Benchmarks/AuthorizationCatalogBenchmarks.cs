// <copyright file="AuthorizationCatalogBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using BenchmarkDotNet.Attributes;
using Norge360.Auth.Application.Security;
using Norge360.Auth.Domain.Entities;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class AuthorizationCatalogBenchmarks
{
    private User _adminUser = default!;
    private User _ownerUser = default!;
    private string[] _adminRoles = default!;
    private string[] _mixedRoles = default!;
    private string[] _serializedValues = default!;

    [GlobalSetup]
    public void Setup()
    {
        _adminUser = new User
        {
            Roles = "tenant-admin,tenant-user",
            Permissions = "customers.read,customers.write,session:self"
        };
        _ownerUser = new User
        {
            Roles = "tenant-owner",
            Permissions = "*"
        };
        _adminRoles = [AuthorizationCatalog.Roles.TenantAdmin, AuthorizationCatalog.Roles.TenantUser];
        _mixedRoles = [AuthorizationCatalog.Roles.TenantAdmin, "unknown-role", AuthorizationCatalog.Roles.TenantUser];
        _serializedValues = [" customers.read ", "customers.write", "customers.read", "session:self"];
    }

    [Benchmark] public int RolesCatalog_Count() => AuthorizationCatalog.RolesCatalog.Count;
    [Benchmark] public int PermissionCatalog_Count() => AuthorizationCatalog.PermissionCatalog.Count;
    [Benchmark] public RoleDefinition? FindRole_Admin() => AuthorizationCatalog.FindRole(AuthorizationCatalog.Roles.TenantAdmin);
    [Benchmark] public RoleDefinition? FindRole_Unknown() => AuthorizationCatalog.FindRole("unknown-role");
    [Benchmark] public bool IsKnownRole_Admin() => AuthorizationCatalog.IsKnownRole(AuthorizationCatalog.Roles.TenantAdmin);
    [Benchmark] public bool IsKnownRole_Unknown() => AuthorizationCatalog.IsKnownRole("unknown-role");
    [Benchmark] public int HighestRoleRank_AdminUser() => AuthorizationCatalog.HighestRoleRank(_adminRoles);
    [Benchmark] public int HighestRoleRank_Mixed() => AuthorizationCatalog.HighestRoleRank(_mixedRoles);
    [Benchmark] public bool HasRole_Admin() => AuthorizationCatalog.HasRole(_adminUser, AuthorizationCatalog.Roles.TenantAdmin);
    [Benchmark] public bool HasRole_Missing() => AuthorizationCatalog.HasRole(_adminUser, AuthorizationCatalog.Roles.TenantOwner);
    [Benchmark] public bool HasPermission_Admin_Read() => AuthorizationCatalog.HasPermission(_adminUser, AuthorizationCatalog.Permissions.CustomersRead);
    [Benchmark] public bool HasPermission_Admin_Delete() => AuthorizationCatalog.HasPermission(_adminUser, AuthorizationCatalog.Permissions.CustomersDelete);
    [Benchmark] public bool HasPermission_Owner_Wildcard() => AuthorizationCatalog.HasPermission(_ownerUser, AuthorizationCatalog.Permissions.CustomersDelete);
    [Benchmark] public IReadOnlyCollection<string> ResolvePermissions_FromAdminRole() => AuthorizationCatalog.ResolvePermissions(_adminRoles);
    [Benchmark] public IReadOnlyCollection<string> ResolvePermissions_WithExplicit() => AuthorizationCatalog.ResolvePermissions(_adminRoles, ["custom.permission", "session:self"]);
    [Benchmark] public IReadOnlyCollection<string> ResolvePermissions_MixedRoles() => AuthorizationCatalog.ResolvePermissions(_mixedRoles);
    [Benchmark] public string Serialize_Distinct() => AuthorizationCatalog.Serialize(_serializedValues);
    [Benchmark] public string Serialize_Empty() => AuthorizationCatalog.Serialize([]);
}
