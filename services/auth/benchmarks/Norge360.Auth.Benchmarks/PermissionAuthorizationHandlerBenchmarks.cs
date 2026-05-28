// <copyright file="PermissionAuthorizationHandlerBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Authorization;
using Norge360.Auth.API.Permissions;

namespace Norge360.Auth.Benchmarks;

[MemoryDiagnoser]
public class PermissionAuthorizationHandlerBenchmarks
{
    private readonly PermissionAuthorizationHandler _handler = new();
    private readonly PermissionRequirement _requirement = new("auth:users:read");
    private AuthorizationHandlerContext _allowContext = default!;
    private AuthorizationHandlerContext _denyContext = default!;

    [GlobalSetup]
    public void Setup()
    {
        _allowContext = CreateContext(
            new Claim("tenant_id", Guid.NewGuid().ToString("D")),
            new Claim("permission", "auth:users:read"));

        _denyContext = CreateContext(
            new Claim("tenant_id", Guid.NewGuid().ToString("D")),
            new Claim("permission", "auth:users:write"));
    }

    [Benchmark]
    public Task Allow_SpecificPermission() => _handler.HandleAsync(_allowContext);

    [Benchmark]
    public Task Deny_PermissionMismatch() => _handler.HandleAsync(_denyContext);

    private AuthorizationHandlerContext CreateContext(Claim tenantClaim, Claim permissionClaim)
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity([tenantClaim, permissionClaim], "bench"));
        return new AuthorizationHandlerContext([_requirement], principal, resource: null);
    }
}
