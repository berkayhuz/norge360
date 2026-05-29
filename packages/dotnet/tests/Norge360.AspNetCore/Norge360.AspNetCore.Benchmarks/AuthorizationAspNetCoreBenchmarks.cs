// <copyright file="AuthorizationAspNetCoreBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Authorization;
using Norge360.Authorization.AspNetCore;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class AuthorizationAspNetCoreBenchmarks
{
    private PermissionAuthorizationHandler _handler = null!;
    private PermissionRequirement _requirement = null!;
    private ClaimsPrincipal _user = null!;

    [GlobalSetup]
    public void Setup()
    {
        _handler = new PermissionAuthorizationHandler();
        _requirement = new PermissionRequirement("users.read");
        _user = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("permission", "users.read users.write")
        ], "bench"));
    }

    [Benchmark]
    public async Task HandleRequirement()
    {
        var context = new AuthorizationHandlerContext([_requirement], _user, null);
        await _handler.HandleAsync(context);
    }
}
