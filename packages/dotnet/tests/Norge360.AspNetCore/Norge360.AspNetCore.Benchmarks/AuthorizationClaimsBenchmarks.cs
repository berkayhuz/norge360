// <copyright file="AuthorizationClaimsBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using BenchmarkDotNet.Attributes;
using Norge360.Authorization.Claims;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class AuthorizationClaimsBenchmarks
{
    private ClaimsPrincipal _principal = null!;

    [GlobalSetup]
    public void Setup()
    {
        _principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("permission", "users.read users.write orders.read"),
            new Claim("scope", "invoices.read,customers.read"),
            new Claim(ClaimTypes.Role, "admin,reporter")
        ], "bench"));
    }

    [Benchmark(Baseline = true)]
    public IReadOnlyCollection<string> ReadPermissions() => PermissionClaimReader.ReadPermissions(_principal);

    [Benchmark]
    public IReadOnlyCollection<string> ReadRoles() => PermissionClaimReader.ReadRoles(_principal);

    [Benchmark]
    public bool HasPermission() => PermissionClaimReader.HasPermission(_principal, "users.read");
}
