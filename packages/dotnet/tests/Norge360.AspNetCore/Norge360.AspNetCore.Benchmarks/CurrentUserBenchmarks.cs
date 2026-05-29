// <copyright file="CurrentUserBenchmarks.cs" company="Norge360">
// Copyright (c) 2026 Norge360. All rights reserved.
// Norge360 is proprietary software. See the LICENSE file in the repository root.
// </copyright>

using System.Security.Claims;
using BenchmarkDotNet.Attributes;
using Microsoft.AspNetCore.Http;
using Norge360.AspNetCore.CurrentUser;

namespace Norge360.AspNetCore.Benchmarks;

[MemoryDiagnoser]
public class CurrentUserBenchmarks
{
    private HttpCurrentUserService _service = null!;

    [GlobalSetup]
    public void Setup()
    {
        var context = new DefaultHttpContext();
        context.User = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim(ClaimTypes.NameIdentifier, "4b75f7f4-c7e6-4d48-b8a4-c838c6fd4ec2"),
            new Claim(ClaimTypes.Name, "benchmark-user"),
            new Claim(ClaimTypes.Email, "bench@norge360.local")
        ], "benchmark"));

        _service = new HttpCurrentUserService(new HttpContextAccessor { HttpContext = context });
    }

    [Benchmark]
    public Guid ReadUserId() => _service.UserId;

    [Benchmark]
    public bool ReadIsAuthenticated() => _service.IsAuthenticated;
}
